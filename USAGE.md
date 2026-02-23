# USAGE INSTRUCTIONS

RPKM → PCA → Single-Cell Inference Workshop

This repository is a fully self-contained analysis for exploring bulk RPKM data using PCA and downstream inference concepts (e.g. contrasts, convex hull novelty).

You do not need to install Python or anything else used in the repo here manually.
Everything is handled automatically by the setup scripts.

⸻

🚀 Quick Start (Recommended)

What you need
* A laptop running Windows or macOS
* Internet access (for first-time setup only)

That’s it.

⸻

🧩 One-Time Setup (5–10 minutes)

📌 Windows
1. Open the repository folder
2.	Double-click:

```scripts\setup_windows.ps1```

If Windows blocks it, copy-paste this once into PowerShell:

```powershell -ExecutionPolicy Bypass -File scripts\setup_windows.ps1```

Then press Enter.

⸻

🍎 macOS
	1.	Open the repository folder
	2.	Double-click:

```scripts/setup_mac.command```

If macOS warns you:
* Right-click the file
* Choose Open
* Click Open again

(This is normal for unsigned scripts.)

⸻

What the setup script does (automatically)

You don’t need to do anything during this process.

The script will:
1. Install Miniforge (a lightweight Python environment manager), if needed
2.	Install mamba (fast dependency solver), if needed
3.	Create the workshop environment from environment.workshop.yml
4.	Run a smoke test to verify all packages
5.	Print a diagnostic summary (useful if troubleshooting)
6.	Register a Jupyter kernel
7.	Launch JupyterLab and open the workshop notebook

When setup finishes successfully, you’ll see:

```SUCCESS ✅  Environment ready. Launching the notebook now…```


⸻

📓 Running the Workshop Notebook

The setup script automatically opens:

```notebooks/workshop.ipynb```

You are now ready to work.

Important
* Use the kernel named rpkm-workshop
* The notebook is designed to run top-to-bottom

⸻

🔁 Opening the Notebook Later (After Setup)

You do not need to reinstall anything.

Windows

Double-click:

```scripts\launch_windows.ps1```

macOS

Double-click:

```scripts/launch_mac.command```

That’s it — JupyterLab will open with the correct environment.

⸻

🧠 Optional method for launching this notebook: Terminal Usage

If you are comfortable with the terminal, you can run the following:

Windows (PowerShell)

```conda run -n rpkm-workshop jupyter lab notebooks\workshop.ipynb```

macOS (Terminal)

```conda run -n rpkm-workshop jupyter lab notebooks/workshop.ipynb```

You do not need to conda activate unless you want to.

⸻

🔧 Troubleshooting

If anything goes wrong:

1️⃣ Re-run setup

The setup scripts are safe to re-run and will repair the environment.

2️⃣ Screenshot diagnostics

During setup, the script prints:
* OS + architecture
* Python version
* Package versions
* Network check

If you need help, screenshot that section.