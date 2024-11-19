# Anatomically Targeted-Automated Tractography (AT-AT)

Developed by: [lawrence.binding.19@ucl.ac.uk](mailto:lawrence.binding.19@ucl.ac.uk)

## Introduction

Anatomically Targeted-Automated Tractography (AT-AT) is a collection of bash scripts designed to perform tractography based on the anatomical terminations of fibre bundles. The tractography is constrained by data from 10 healthy control subjects with 7T diffusion MRI scans from the Human Connectome Project (HCP). 

## Requirements

- **Operating System**: Mac or Linux
- **Freesurfer**: Version 7.4 or higher
- **MRtrix3**: Installed
- **Python**: Installed

## Installation

1. **Download the repository** and place it in a desired directory. For example, you can place it at `/Users/lawrence/` (this path will be referred to as `<path>`).

2. **Set the script path**: 
   After downloading the repository, you need to add the path to the `scripts` directory in your `bashrc`. Replace `<path>` with the actual path where the software is installed:

```bash
echo 'export PATH="<path>/AT-AT/scripts:$PATH"' >> ~/.bashrc
```
For example, if you installed the software in /Users/lawrence/:
```bash
echo 'export PATH="/Users/lawrence/AT-AT/scripts:$PATH"' >> ~/.bashrc
```

Source the updated bashrc:
To apply the changes, either close and reopen your terminal or run:

```bash
source ~/.bashrc
```

Install the required Python packages:
Navigate to the repository directory and install the required Python dependencies via pip:

```bash
pip install -r requirements.txt
```

This will install all necessary packages for running the scripts.

## Usage
Once everything is set up, you can call the scripts directly from your terminal. Here’s an example:

```bash
ATAT_AF.sh -gif gif_parc.nii.gz -T1 T1.nii.gz -fivett 5tt_hsvs.nii.gz -FOD wm.mif -out_dir ATAT2_Tractography/
```

Available Scripts
The scripts currently available in this release (as of 19/11/2024) include:
- ATAT_AF.sh

Script Options
These are the available options for running the scripts:

- -gif: Input GIF parcellation (REQUIRED)
- -T1: Input T1 parcellation (REQUIRED)
- -fivett: Input 5tt image (REQUIRED)
- -FOD: Input CSD image (REQUIRED)
- -out_dir: Output folder for all preprocessing and tracts (REQUIRED)
- -roi_dir: Output folder for tract ROIs (OPTIONAL)
- -niftyReg: Use NiftyReg instead of easyReg registration tract mask (OPTIONAL)
- -alg: Select default algorithm: det or prob (default=prob) (OPTIONAL)
- -threads: Select the number of threads for easyReg to use (default=10) (OPTIONAL)

Example Commands

An example showing all options and their usage:

```bash
ATAT_AF.sh -gif gif_parc.nii.gz -T1 T1.nii.gz -fivett 5tt_hsvs.nii.gz -FOD wm.mif -out_dir ATAT2_Tractography/ -roi_dir ATAT2_Tractography/roi/ -niftyReg -alg det -threads 15
```

## Output
Based on the basic commands, there will be .tck files present in ATAT2_Tractography/ which you can use for analysis.

