

# Bulk PCA as a Metric for snRNA-seq Inference

This workshop leverages control-only bulk RNA-seq's higher-level, holistic traits while avoiding the following pitfalls:
1. Treating bulk-seq. contents as TPM or UMI counts
2. Using bulk-seq. as a ground truth for log-fold-change, 
3. Using bulk-seq. to compare absolute expression values against this data 
4. Using bulk-seq. for finding DEGs. 

The core idea is simple:

Bulk PCA defines a biologically grounded coordinate system.
Single-nucleus states can be interpreted by projection into that space.

This repository provides a fully reproducible pipeline to operationalize this idea.

⸻

Conceptual Pipeline
1.	Learn stable bulk PCs (“programs”) from control-only bulk RNA-seq
(e.g. RPKM / TPM across tissues, genotypes, conditions).
2.	Project each nucleus (snRNA-seq) into this bulk PC space
→ each cell receives program scores.
3.	Define cell–cell distance as Euclidean distance in bulk PC space
(not raw gene space).
4.	Construct graphs / neighbors / trajectories using this biologically informed metric.
5.	Use program scores as covariates or coordinates to stabilize:
    * clustering
    * state inference
    * trajectory analysis
    * differential expression
    * contrast-based interpretation (e.g. “bam-ness”)

Bulk PCA is treated as a reference manifold here.

⸻

🚀 Workshop Quick Start (No Python Setup Required!)

You do not need to install Python, pip, or virtual environments manually.

Step 1 — Get the repository files

Recommended (works on Windows & macOS):
1. Click Code → Download ZIP
2. Unzip the folder

(Advanced users may clone with git if preferred.)

⸻

Step 2 — One-click setup

From inside the repository folder:

🪟 Windows
Double-click:

```scripts\setup_windows.bat```
Do not run as Administrator.

🍎 macOS
Double-click:

```scripts/setup_mac.command```

If macOS warns you:
1. Right-click → Open
2. Click Open again

⸻

What the setup script does (automatically)
1. Installs Miniforge (lightweight conda) if needed
2. Installs mamba (fast solver) if needed
3. Creates / updates the workshop environment from environment.workshop.yml
4. Runs a smoke test and prints a diagnostic summary
5. Registers a Jupyter kernel
6. Launches JupyterLab and opens the workshop notebook

When you see:

SUCCESS ✅  Environment ready. Launching the notebook now…

you’re ready.

⸻

📓 Running the Workshop Notebook

The setup script automatically opens:

```notebooks/workshop.ipynb```

Use the kernel named:

```rpkm-workshop```

The notebook is designed to run top-to-bottom.

⸻

🔁 Re-opening the Notebook Later

You do not need to reinstall anything.

Windows

Double-click:

```scripts\launch_windows.ps1```

macOS

Double-click:

```scripts/launch_mac.command```


⸻

🧬 What You Provide

1) Bulk RNA-seq (controls only)
* A samples × genes table (CSV or TSV)
* Expression values: RPKM or TPM
* Used only to learn stable reference PCs

Example:

```sample × gene  →  PCA  →  bulk programs```

2) snRNA-seq
* An AnnData (.h5ad) object, or
* A cells × genes matrix loadable into Python

Cells are projected, not refit.

See data/README.md for exact formats.

⸻

🧠 Why This Framing Matters

This approach:
* decouples state geometry from noisy single-cell sampling
* anchors inference in validated bulk biology
* avoids redefining axes per experiment
* enables principled contrasts (e.g. genotype, tissue, sex)

In short:
bulk defines the coordinate system; single cells are interpreted within it.

⸻

🔧 Updating the Environment (If the Repo Changes)

If new dependencies are added in the future:

Simply re-run the setup script.

It safely updates the environment in place.

📁 Repository Structure

```
├── environment.workshop.yml (defines packages used)
├── notebooks/
│   └── workshop.ipynb (analysis notebook)
├── scripts/
│   ├── setup_windows.ps1 (install)       
│   ├── launch_windows.ps1 (reopening)      
│   ├── setup_mac.command  (install)
│   └── launch_mac.command (reopening)
└── USAGE.md (usage instructions)
|__ README.md (repo topic description)
```

⸻

🎯 Workshop Philosophy:
* No manual Python installs
* No environment debugging
* No dependency guesswork
* One click → working notebook

If setup succeeds once, you’re good for the entire workshop.