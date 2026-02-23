"""Bulk PCA as a *metric* for snRNA-seq inference.

This module implements a simple idea:

1) Learn principal components (PCs) from **control-only bulk RNA-seq** (RPKM/TPM).
2) Project each snRNA nucleus into that bulk PC space to obtain **program scores**.
3) Compare nuclei using Euclidean distance between their program-score vectors.

Why it helps (intuition for biologists)
--------------------------------------
- snRNA-seq has many dimensions that are dominated by technical noise, dropout, and
  idiosyncratic variation.
- Control bulk RNA-seq (when well-powered) captures *replicable* biological axes.

By measuring distances only along the bulk-validated axes, you:
- ignore many snRNA-only noise dimensions, and
- stabilize neighborhood graphs, clustering, trajectories, and transitions.

Data expectations
----------------
Bulk (controls only)
- Provide a table with **rows = samples** and **columns = genes**.
- Values are **non-negative** RPKM or TPM.
- We treat RPKM/TPM as *geometry*: we use ``log1p(RPKM)`` and per-gene z-scoring
  across bulk samples. (No differential expression is performed on bulk here.)

snRNA-seq
- Provide a matrix with **rows = nuclei** and **columns = genes**.
- ``project_log1p_to_bulk_pcs`` expects **log1p-normalized expression**
  (e.g. log1p(CP10K) or log1p(size-factor-normalized counts)).
- Gene identifiers must match the bulk model gene identifiers as closely as
  possible (same namespace, casing, versioning).
"""

from __future__ import annotations

import json
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any, Literal, Sequence

import numpy as np
import pandas as pd
from scipy.optimize import linear_sum_assignment
from sklearn.decomposition import PCA
from sklearn.neighbors import NearestNeighbors

MissingGenesPolicy = Literal["error", "warn", "ignore"]


def _as_path(path: str | Path) -> Path:
    return path if isinstance(path, Path) else Path(path)


@dataclass
class BulkPCAModel:
    """
    A compact, reusable “bulk program” model (PCA + scaling statistics).

    Think of this as a *coordinate system* learned from control bulk RNA-seq.
    It is intentionally minimal: everything you need to project new data
    (snRNA nuclei) into the same bulk PC space.

    Attributes
    ----------
    genes
        Ordered list of genes used to fit the model (length G).
    mean_
        Per-gene mean of bulk ``log1p(RPKM/TPM)`` across control samples (length G).
    scale_
        Per-gene standard deviation used for z-scoring across bulk samples
        (length G). Genes with zero variance are excluded during fitting.
    loadings_
        PCA loadings matrix with shape (G, K). Columns correspond to PCs.
        A nucleus’ program-score vector ``s`` is computed as:

        ``s = ((x_log1p - mean_) / scale_) @ loadings_``

        Note: PC signs are arbitrary; flipping a PC sign does not change distances.
    explained_variance_, explained_variance_ratio_
        Standard PCA diagnostics (optional).
    metadata
        Free-form metadata to help provenance (filters, parameters, etc.).
    """
    genes: np.ndarray  # (G,)
    mean_: np.ndarray  # (G,)
    scale_: np.ndarray  # (G,)
    loadings_: np.ndarray  # (G, K) where columns are PCs
    explained_variance_: np.ndarray | None = None  # (K,)
    explained_variance_ratio_: np.ndarray | None = None  # (K,)
    metadata: dict[str, Any] = field(default_factory=dict)

    def __post_init__(self) -> None:
        self.genes = np.asarray(self.genes, dtype=str)
        self.mean_ = np.asarray(self.mean_, dtype=float)
        self.scale_ = np.asarray(self.scale_, dtype=float)
        self.loadings_ = np.asarray(self.loadings_, dtype=float)

        if self.genes.ndim != 1:
            raise ValueError("genes must be 1D")
        if self.mean_.shape != self.genes.shape:
            raise ValueError("mean_ must have shape (n_genes,)")
        if self.scale_.shape != self.genes.shape:
            raise ValueError("scale_ must have shape (n_genes,)")
        if self.loadings_.ndim != 2 or self.loadings_.shape[0] != self.genes.shape[0]:
            raise ValueError("loadings_ must have shape (n_genes, n_pcs)")

    @property
    def n_genes(self) -> int:
        return int(self.genes.shape[0])

    @property
    def n_pcs(self) -> int:
        return int(self.loadings_.shape[1])

    def subset_pcs(self, pcs: Sequence[int]) -> "BulkPCAModel":
        """
        Return a new model that keeps only a subset of PCs.

        This is typically used after you decide which PCs are “stable” under
        bootstrap (see ``bootstrap_pc_stability``).

        Parameters
        ----------
        pcs
            0-based PC indices to keep.
        """
        pcs = np.asarray(list(pcs), dtype=int)
        return BulkPCAModel(
            genes=self.genes.copy(),
            mean_=self.mean_.copy(),
            scale_=self.scale_.copy(),
            loadings_=self.loadings_[:, pcs],
            explained_variance_=None if self.explained_variance_ is None else self.explained_variance_[pcs],
            explained_variance_ratio_=None
            if self.explained_variance_ratio_ is None
            else self.explained_variance_ratio_[pcs],
            metadata=dict(self.metadata),
        )

    def save_npz(self, path: str | Path) -> None:
        """
        Save the model as a single compressed ``.npz`` file.

        This is the main artifact you keep from the bulk “program learning” step.
        Share this file with collaborators so everyone projects nuclei into the
        same bulk PC space.
        """
        path = _as_path(path)
        payload = {
            "genes": self.genes,
            "mean_": self.mean_,
            "scale_": self.scale_,
            "loadings_": self.loadings_,
            "explained_variance_": self.explained_variance_,
            "explained_variance_ratio_": self.explained_variance_ratio_,
            "metadata_json": np.asarray(json.dumps(self.metadata), dtype=str),
        }
        np.savez_compressed(path, **{k: v for k, v in payload.items() if v is not None})

    @classmethod
    def load_npz(cls, path: str | Path) -> "BulkPCAModel":
        """
        Load a model previously saved with ``save_npz``.

        Parameters
        ----------
        path
            Path to a ``.npz`` produced by ``BulkPCAModel.save_npz``.
        """
        path = _as_path(path)
        with np.load(path, allow_pickle=False) as data:
            metadata = json.loads(str(data.get("metadata_json", "{}")))
            return cls(
                genes=data["genes"].astype(str),
                mean_=data["mean_"].astype(float),
                scale_=data["scale_"].astype(float),
                loadings_=data["loadings_"].astype(float),
                explained_variance_=data.get("explained_variance_", None),
                explained_variance_ratio_=data.get("explained_variance_ratio_", None),
                metadata=metadata,
            )


def fit_bulk_pca_model(
    bulk_rpkm: pd.DataFrame,
    *,
    gene_min_frac: float = 0.25,
    n_components: int = 50,
    random_state: int = 0,
) -> tuple[BulkPCAModel, np.ndarray]:
    """
    Fit a bulk PCA “program” model on control-only bulk RPKM/TPM.

    Biologist-friendly view
    -----------------------
    Bulk RPKM/TPM is allowed here because we only use it to learn a *shape* of
    biological variation across control samples.

    Steps performed:
    1) ``X = log1p(RPKM_or_TPM)``
    2) Filter genes that are rarely expressed across bulk samples
    3) Per-gene z-score across bulk samples (store mean/std!)
    4) PCA on the z-scored bulk matrix

    The output ``BulkPCAModel`` is what you save and reuse to score snRNA nuclei.

    Parameters
    ----------
    bulk_rpkm
        DataFrame of shape (n_bulk_samples, n_genes).

        - rows = **bulk samples** (controls only)
        - columns = **genes** (symbols or Ensembl IDs)
        - values = **non-negative** RPKM or TPM

        Practical tips:
        - Use the same gene identifier convention you use in snRNA (to maximize overlap).
        - You want enough samples that PCA is stable (dozens is better than <10).
    gene_min_frac
        Keep genes expressed (RPKM>0) in at least this fraction of bulk samples.

        This is not about biology so much as numerical stability: genes that are
        almost always zero in bulk contribute little to replicable PCs.
    n_components
        Requested number of PCs (will be clipped by data rank).

        Common practice: start with 50, then *select PCs by stability* via
        ``bootstrap_pc_stability``.
    random_state
        Used by sklearn PCA when randomized solver is selected.

    Returns
    -------
    model, bulk_scores
        ``bulk_scores`` are the bulk samples projected into PC space (n_samples, K).

    Example
    -------
    >>> bulk = pd.read_csv("bulk_controls_rpkm.tsv", sep="\\t", index_col=0)
    >>> model, bulk_scores = fit_bulk_pca_model(bulk, n_components=50)
    >>> model.save_npz("bulk_pca_model.npz")
    """
    if bulk_rpkm.shape[0] < 3:
        raise ValueError("Need at least 3 bulk samples for PCA stability.")

    if bulk_rpkm.columns.has_duplicates:
        dupes = bulk_rpkm.columns[bulk_rpkm.columns.duplicated()].unique().tolist()
        raise ValueError(f"bulk_rpkm has duplicated gene columns (first few): {dupes[:10]}")

    r = bulk_rpkm.copy()
    if (r.to_numpy(dtype=float, copy=False) < 0).any():
        raise ValueError("bulk_rpkm contains negative values; expected non-negative RPKM/TPM.")
    r = r.loc[:, (r > 0).mean(axis=0) >= gene_min_frac]
    if r.shape[1] == 0:
        raise ValueError("No genes pass bulk gene_min_frac filter.")

    x = np.log1p(r.to_numpy(dtype=float, copy=False))
    mu = x.mean(axis=0)
    sigma = x.std(axis=0, ddof=0)

    nonzero = sigma > 0
    if not np.all(nonzero):
        r = r.loc[:, nonzero]
        x = x[:, nonzero]
        mu = mu[nonzero]
        sigma = sigma[nonzero]

    z = (x - mu) / sigma

    k = int(min(n_components, z.shape[0] - 1, z.shape[1]))
    if k < 1:
        raise ValueError("n_components is too large for the bulk matrix rank.")

    pca = PCA(n_components=k, svd_solver="auto", random_state=random_state)
    bulk_scores = pca.fit_transform(z)
    loadings = pca.components_.T  # (genes, pcs)

    model = BulkPCAModel(
        genes=r.columns.to_numpy(dtype=str),
        mean_=mu,
        scale_=sigma,
        loadings_=loadings,
        explained_variance_=getattr(pca, "explained_variance_", None),
        explained_variance_ratio_=getattr(pca, "explained_variance_ratio_", None),
        metadata={
            "gene_min_frac": float(gene_min_frac),
            "n_components_requested": int(n_components),
            "n_components_fit": int(k),
            "transform": "log1p(RPKM_or_TPM)",
            "scaling": "zscore_per_gene_across_bulk_samples",
        },
    )
    return model, bulk_scores


def bootstrap_pc_stability(
    z_bulk: np.ndarray,
    base_loadings: np.ndarray,
    *,
    n_bootstrap: int = 100,
    random_state: int = 0,
) -> np.ndarray:
    """
    Estimate which bulk PCs (“programs”) are *replicable* by bootstrapping samples.

    Intuition
    ---------
    PCA will always return *some* components, but not all components represent
    true biology; later PCs often drift with sampling noise.

    This function answers: “If I slightly perturb my bulk dataset (by resampling
    samples with replacement), do I recover the same programs?”

    How to use
    ----------
    - Compute ``Z_bulk`` the same way PCA was trained: log1p + z-score per gene
      across bulk samples.
    - Run this stability estimate.
    - Keep PCs above a threshold (often 0.8–0.9).

    Notes
    -----
    - PC signs are arbitrary, so we compare loadings using **absolute cosine**
      similarity (sign-invariant).
    - PCs can swap order in bootstrap fits, so we do one-to-one matching with a
      Hungarian assignment.

    Returns a per-PC stability score in [0, 1] computed as the mean best-match
    cosine similarity (sign-invariant) between base PC loading vectors and
    bootstrap PCs, with one-to-one matching (Hungarian assignment).
    """
    if z_bulk.ndim != 2:
        raise ValueError("z_bulk must be 2D (n_samples, n_genes)")
    if base_loadings.ndim != 2:
        raise ValueError("base_loadings must be 2D (n_genes, n_pcs)")
    if z_bulk.shape[1] != base_loadings.shape[0]:
        raise ValueError("z_bulk and base_loadings gene dimensions do not match")

    rng = np.random.default_rng(random_state)
    n_samples, n_genes = z_bulk.shape
    k = base_loadings.shape[1]

    base = base_loadings.T  # (K, G)
    base = base / np.linalg.norm(base, axis=1, keepdims=True)

    sims = np.zeros((n_bootstrap, k), dtype=float)
    for b in range(n_bootstrap):
        idx = rng.integers(0, n_samples, size=n_samples)
        zb = z_bulk[idx, :]

        pca = PCA(n_components=k, svd_solver="auto", random_state=random_state)
        pca.fit(zb)
        boot = pca.components_  # (K, G)
        boot = boot / np.linalg.norm(boot, axis=1, keepdims=True)

        # Similarity matrix: abs cosine between loading vectors (sign-invariant).
        c = np.abs(base @ boot.T)  # (K, K)
        row, col = linear_sum_assignment(-c)
        sims[b, row] = c[row, col]

    return sims.mean(axis=0)


def project_log1p_to_bulk_pcs(
    x_log1p: Any,
    genes: Sequence[str],
    model: BulkPCAModel,
    *,
    on_missing: MissingGenesPolicy = "warn",
    include_missing_offset: bool = True,
) -> tuple[np.ndarray, dict[str, Any]]:
    """
    Project log1p-normalized expression into bulk PC space.

    Biologist-friendly view
    -----------------------
    This computes **program scores** for each nucleus: where does this nucleus
    sit along each bulk-derived biological axis?

    You provide snRNA expression (already normalized + log1p), we line up genes
    to the bulk model, and we compute:

    ``scores = ((X_log1p - mu_bulk) / sigma_bulk) @ loadings``

    Those scores can be used as:
    - features for clustering/state inference
    - a metric space for neighbors (Euclidean in score space)
    - covariates in DE models (control for continuous programs)

    What to pass for snRNA
    ----------------------
    ``x_log1p`` should be the matrix you want to compare nuclei in. Typical
    choices:
    - log1p(CP10K) / log1p(CPM) style normalized expression
    - log1p(size-factor-normalized counts)

    If you only have raw counts, run your lab’s standard normalization + log1p
    first (Scanpy example):

    >>> import scanpy as sc
    >>> sc.pp.normalize_total(adata, target_sum=1e4)
    >>> sc.pp.log1p(adata)
    >>> scores, info = project_log1p_to_bulk_pcs(adata.X, adata.var_names, model)

    Gene matching matters
    --------------------
    Bulk and snRNA must share gene identifiers. If overlap is low, your program
    scores will be noisy or meaningless. Always inspect ``info``.

    Notes
    -----
    - If you mainly care about **cell–cell distances**, the bulk mean term
      cancels out: distances depend on differences like ``(x_i - x_j)``.
      This makes the approach fairly robust to global offsets between bulk and
      snRNA normalization choices.
    - ``include_missing_offset`` affects absolute score baselines but does not
      change distances between nuclei.

    Parameters
    ----------
    x_log1p
        Expression matrix of shape (n_obs, n_genes_in_input). Can be dense (ndarray)
        or scipy sparse.
    genes
        Gene identifiers for columns of x_log1p.
    model
        Bulk PC model.
    on_missing
        What to do if model genes are missing from the input.
    include_missing_offset
        If True, treat missing genes as 0-expression (log1p(0)=0) and include their
        constant contribution so absolute scores match the “filled with zeros” result.
        Distances are unchanged either way.

    Returns
    -------
    scores, info
        scores: (n_obs, K)
        info: dict with missing/present gene counts and gene lists.
    """
    try:
        import scipy.sparse as sp
    except Exception:  # pragma: no cover
        sp = None

    x = x_log1p
    genes = np.asarray(list(genes), dtype=str)
    if genes.ndim != 1:
        raise ValueError("genes must be 1D")

    input_index = {g: i for i, g in enumerate(genes)}

    model_genes = model.genes
    present_model_idx: list[int] = []
    present_input_idx: list[int] = []
    missing_genes: list[str] = []
    for gi, g in enumerate(model_genes):
        j = input_index.get(g)
        if j is None:
            missing_genes.append(g)
        else:
            present_model_idx.append(gi)
            present_input_idx.append(int(j))

    if missing_genes and on_missing == "error":
        raise KeyError(f"Input is missing {len(missing_genes)} / {model.n_genes} model genes.")

    info: dict[str, Any] = {
        "n_model_genes": int(model.n_genes),
        "n_present_genes": int(len(present_model_idx)),
        "n_missing_genes": int(len(missing_genes)),
        "missing_genes": missing_genes if (missing_genes and on_missing == "warn") else [],
    }

    if missing_genes and on_missing == "warn":
        # Keep the list short to avoid flooding notebooks/logs.
        preview = ", ".join(missing_genes[:10])
        suffix = "" if len(missing_genes) <= 10 else f", ... (+{len(missing_genes) - 10} more)"
        info["warning"] = f"Missing {len(missing_genes)} model genes; preview: {preview}{suffix}"

    if len(present_model_idx) == 0:
        raise ValueError("No overlap between input genes and model genes.")

    pm = np.asarray(present_model_idx, dtype=int)
    pi = np.asarray(present_input_idx, dtype=int)

    mu = model.mean_[pm]
    scale = model.scale_[pm]
    load = model.loadings_[pm, :]  # (Gp, K)

    # scores = ((X - mu) / scale) @ load = (X/scale)@load - (mu/scale)@load
    if sp is not None and sp.issparse(x):
        xp = x[:, pi]
        xp_scaled = xp.multiply(1.0 / scale)
        scores = xp_scaled @ load
    else:
        xp = np.asarray(x)[:, pi]
        scores = (xp / scale) @ load

    scores = np.asarray(scores) - (mu / scale) @ load

    if include_missing_offset and len(missing_genes) > 0:
        mmask = np.ones(model.n_genes, dtype=bool)
        mmask[pm] = False
        mu_m = model.mean_[mmask]
        scale_m = model.scale_[mmask]
        load_m = model.loadings_[mmask, :]
        offset = (-mu_m / scale_m) @ load_m  # (K,)
        scores = scores + offset
        info["missing_offset"] = offset

    return scores, info


def knn_indices_distances(
    x: np.ndarray,
    *,
    n_neighbors: int = 30,
    metric: str = "euclidean",
    n_jobs: int = 1,
) -> tuple[np.ndarray, np.ndarray]:
    """
    Compute kNN indices and distances for rows of x.

    In this pipeline, ``x`` is usually the bulk-PC program score matrix
    (nuclei × K). Running kNN on these scores implements the key design:

    **nucleus–nucleus distance = Euclidean distance in bulk PC space**

    You can then build neighbor graphs, trajectories, and transition detection
    on top of this neighbor structure (in Scanpy you would typically call
    ``sc.pp.neighbors(adata, use_rep="X_bulk_pcs")`` instead).

    Returns (indices, distances) with shape (n_obs, n_neighbors), excluding self.
    """
    x = np.asarray(x, dtype=float)
    if x.ndim != 2:
        raise ValueError("x must be 2D (n_obs, n_features)")
    if n_neighbors < 1:
        raise ValueError("n_neighbors must be >= 1")
    if x.shape[0] <= n_neighbors:
        raise ValueError("Need n_obs > n_neighbors")

    nn = NearestNeighbors(n_neighbors=n_neighbors + 1, metric=metric, n_jobs=n_jobs)
    nn.fit(x)
    distances, indices = nn.kneighbors(x, return_distance=True)
    return indices[:, 1:], distances[:, 1:]
