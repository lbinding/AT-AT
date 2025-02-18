#! /usr/bin/env python
#__author__ = 'LB'
import argparse
import os
import numpy as np
import scipy.ndimage.morphology as spmorph
import scipy.ndimage as ndimage
import nibabel as nib

# Framework by Sjoerd Vos (s.vos[at]ucl.ac.uk) for dilating ROIs
#       Edited by Lawrence Binding (lawrence.binding.19[at]ucl.ac.uk) for destrieux parcellation and 5tt ACT
#       Edited by Lawrence Binding (lawrence.binding.19[at]ucl.ac.uk): Removed redundant inputs

def dilate_cortex(hsvs_5tt_wm,in_mask_name, in_ROI_name, out_ROI_name):

    """
    Main function to dilate a cortical input parcel into the neighbouring WM

    Required inputs:
    hsvs_5tt_wm: filename of the 5tt_hsvs parcellation file aligned to DWI space (*.nii.gz)
    in_ROI_name:   filename of the original tract ROI (*.nii.gz)
    out_ROI_name:  filename of the modified tract ROI (*.nii.gz)

    """
     # Derive output directory
    out_dir = os.path.dirname(out_ROI_name)
    if not os.path.isdir(out_dir):
        os.mkdir(out_dir)

    # dilate by margin
    k_size = 3
    se = np.zeros((k_size, k_size, k_size))
    #se[(k_size -1 ) / 2, (k_size - 1) / 2, (k_size - 1) / 2] = 1
    se[int(np.round((k_size -1 ) / 2)), int(np.round((k_size - 1) / 2)), int(np.round((k_size - 1) / 2))] = 1
    se = ndimage.gaussian_filter(se, sigma=(1, 1, 1))
    #se = se >= 0.99*se[(k_size - 1) / 2, (k_size - 1) / 2, 0]
    se = se >= 0.99*se[(int(np.round((k_size - 1) / 2))), (int(np.round((k_size - 1) / 2))), 0]

    # Load niftis
    hsvs_5tt_dw_nii = nib.load(hsvs_5tt_wm)
    hsvs_5tt = hsvs_5tt_dw_nii.get_fdata()
    in_mask_nii = nib.load(in_mask_name)
    in_mask = in_mask_nii.get_fdata()
    in_ROI_nii = nib.load(in_ROI_name)
    in_ROI = in_ROI_nii.get_fdata()

    # Index to get white matter
    hsvs_5tt_wm = hsvs_5tt[:, :, :, 2]

    # Get overlap of white matter and mask
    mask_act_overlap = np.logical_and(hsvs_5tt_wm,in_mask)

    # Get volume
    ROI_vol = in_ROI.sum()

    # Dilate cortical parcel
    ROI_dil = spmorph.binary_dilation(in_ROI, se)

    # Divide volume by 1.5, if there isn't this much crossover, redilate
    overlap_ROI_hsvs = np.logical_and(ROI_dil, mask_act_overlap > 0.1)
    while overlap_ROI_hsvs.sum() < (ROI_vol/6):
        ROI_dil = spmorph.binary_dilation(ROI_dil, se)
        overlap_ROI_hsvs = np.logical_and(ROI_dil, mask_act_overlap > 0.1)

    # Get overlap and add to original ROI
    ROI_out = np.logical_and(ROI_dil, mask_act_overlap) + in_ROI

    # Save to image
    nib.save(nib.Nifti1Image(ROI_out, in_ROI_nii.affine, in_ROI_nii.header),
            out_ROI_name)


# inputs
parser = argparse.ArgumentParser()
parser.add_argument('--hsvs_5tt', dest='hsvs_5tt_wm', help='hsvs_5tt in DWI space (*.nii.gz)', required=True)
parser.add_argument('--mask', dest='in_mask_name', help='Input mask (*.nii.gz)', required=True)
parser.add_argument('--in', dest='ROI_in', help='Input ROI to modify (*.nii.gz)', required=True)
parser.add_argument('--out', dest='ROI_out', help='Output ROI filename to save to (*.nii.gz)', required=True)
args = parser.parse_args()

# call function to do correction
dilate_cortex(os.path.abspath(args.hsvs_5tt_wm),os.path.abspath(args.in_mask_name), os.path.abspath(args.ROI_in), os.path.abspath(args.ROI_out))


# cd /data/p1704autoFT/Oeslle/multishell/aylj/test_FT_perilesional
# ~/Public_scripts/FT_perilesional.py --lesion=lesion.nii.gz --parc=../tracts/mtcsd/gif_parc.nii.gz --act=../tracts/mtcsd/FT_5tt.nii.gz --fod=../tracts/mtcsd/wm.mif --out=. --tracts=5 --margin=5
