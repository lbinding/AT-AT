#!/bin/bash
#
# Arcuate Fasciculus AT-ATv2
#   Based off anatomical terminations of: 
#       https://academic.oup.com/brain/article/145/4/1242/6526361?login=true
#   Utilises 7T anatomical priors from HCP subjects
#
# Created by Lawrence Binding 19/11/2024

# Get script name
script_name=`basename $0`

# Get script location
main_dir="$(dirname "$(realpath "$BASH_SOURCE")")/.."
script_path="$(dirname "$(realpath "$BASH_SOURCE")")"
anatomical_priors=${main_dir}/anatomical_priors/

# Assign scripts to varaibles
dilation=${script_path}/Dilate_mask.py
pruning=${script_path}/prune_tck.sh
ROIsplit=${script_path}/split_parcel_long_axis.py

# Setup default Variables
niftyReg="false"
threads=10

# Check to see if MRtrix3 is installed
if ! command -v tckgen &> /dev/null; then
    echo ----------
    echo "MRtrix3 tckgen command is not found..."
    echo "Have you got MRtrix3 installed and correctly setup?"
    echo "exiting..." 
    echo ----------
    exit 
fi

# Loop over arguments looking for -i and -o
args=("$@")
i=0
while [ $i -lt $# ]; do
    if ( [ ${args[i]} = "-gif" ] || [ ${args[i]} = "-g" ] ) ; then
      # Set destrieux parcellation
      let i=$i+1
      gif_parc=${args[i]}
    elif ( [ ${args[i]} = "-T1" ] || [ ${args[i]} = "-t1" ] ) ; then
      # Set gif parcellation
      let i=$i+1
      T1=${args[i]}
    elif ( [ ${args[i]} = "-fivett" ] ) ; then
      # Set fivett 
      let i=$i+1
      fivett=${args[i]}
    elif ( [ ${args[i]} = "-FOD" ] || [ ${args[i]} = "-fod" ] ) ; then
      # Set FOD 
      let i=$i+1
      FOD=${args[i]}
    elif ( [ ${args[i]} = "-output" ] || [ ${args[i]} = "-o" ] || [ ${args[i]} = "-out" ] || [ ${args[i]} = "-out_dir" ]) ; then
      # Set output dir 
      let i=$i+1
      out_dir=${args[i]}
    elif ( [ ${args[i]} = "-roi_dir" ] || [ ${args[i]} = "-roi" ]) ; then
      # Set ROI dir 
      let i=$i+1
      base_roi_dir=${args[i]}
    elif ( [ ${args[i]} = "-niftyReg" ] ) ; then
      # Set ROI dir 
      let i=$i+1
      niftyReg="true"
    elif ( [ ${args[i]} = "-alg" ] ) ; then
      # Set ROI dir 
      let i=$i+1
      algorithm=${args[i]}
    elif ( [ ${args[i]} = "-threads" ] ) ; then
      # Set ROI dir 
      let i=$i+1
      threads=${args[i]}
    fi
    let i=$i+1
done

# Check if user gave correct inputs
if ( [ -z ${gif_parc} ] || [ -z ${fivett} ] || [ -z ${FOD} ] || [ -z ${T1} ]) ; then
    correct_input=0
else 
    correct_input=1
fi

#Set algorithm
if ( [ "${algorithm}" == "prob" ] ) ; then
    algorithm=iFOD2
    options="-backtrack -cutoff 0.1"
  elif ( [ "${algorithm}" == "det" ] ) ; then
    algorithm=SD_Stream
  elif ( [ -z ${algorithm} ] ) ; then
    algorithm=iFOD2
    options="-backtrack -cutoff 0.1"
  else 
  echo "Algorithm not recognised, please select 'det' or 'prob'"
  exit 
fi

#Check the user has provided the correct inputs
if ( [[ ${correct_input} -eq 0 ]] ) ; then
  echo ""
  echo "Incorrect input. Please see below for correct use"
  echo ""
  echo "Options:"
  echo " -gif:          Input GIF parcellation -- REQUIRED"
  echo " -T1:           Input T1 parcellation -- REQUIRED"
  echo " -fivett:       Input 5tt image -- REQUIRED"  
  echo " -FOD:          Input CSD image -- REQUIRED"  
  echo " -out_dir:      Output folder for all preprocessing and tracts -- REQUIRED"  
  echo " -roi_dir:      Output folder for tract ROIs -- OPTIONAL"  
  echo " -niftyReg:     Use NiftyReg registration tract mask -- OPTIONAL"  
  echo " -alg:          Select default algorithm: det or prob (default=prob) -- OPTIONAL" 
  echo " -threads:      Select number of threads for easyReg to use (default=10) -- OPTIONAL"  
  echo ""
  echo "Basic..."
  echo "${script_name} -gif gif_parc.nii.gz -T1 T1.nii.gz -fivett 5tt_hsvs.nii.gz -FOD wm.mif -out_dir ATAT2_Tractography/"
  echo "All options..."
  echo "${script_name} -gif gif_parc.nii.gz -T1 T1.nii.gz -fivett 5tt_hsvs.nii.gz -FOD wm.mif -out_dir ATAT2_Tractography/ -roi_dir ATAT2_Tractography/roi/ -niftyReg -alg det -threads 15"
  echo ""
  exit
fi


# If niftyReg is false check to see if mri_easyreg is installed
if [ ${niftyReg} = "false" ]; then
    if ! command -v mri_easyreg &> /dev/null; then
        echo "----------"
        echo "mri_easyreg doesn't exist..."
        echo "Have you got Freesurfer installed?"
        echo "Have you got Freesurfer >= version 7.4?"
        echo "exiting..."
        echo "----------"
        exit
    fi 
# Else check whether niftyReg is installed 
else
    if ! command -v reg_aladin &> /dev/null; then
        echo ----------
        echo "reg_aladin doesn't exist..."
        echo "Niftyreg installed?"
        echo "Did you mean to use niftyreg instead of easyReg?"
        echo "exiting..." 
        echo ----------
        exit
    fi
fi 

#Check if the gif parcellation image exists 
if [ ! -f ${gif_parc} ]; then 
    echo ----------
    echo "GIF parcellation image does not exist, please check inputs"
    echo ----------
    exit 
fi 
#Check if the T1 image exists 
if [ ! -f ${T1_input} ]; then 
    echo ----------
    echo "T1 image does not exist, please check inputs"
    echo ----------
    exit 
fi 
#Check if the FOD image exists 
if [ ! -f ${FOD_input} ]; then 
    echo ----------
    echo "FOD image does not exist, please check inputs"
    echo ----------
    exit 
fi 

#Check that the GIF parcellation has a max number of 208
if [ -f ${gif_parc} ]; then 
    gif_parc_max=`mrstats ${gif_parc} -output max`
    if [ ${gif_parc_max} -ne 208 ]; then 
        echo ----------
        echo "WARNING"
        echo ----------
        echo "The gif parellation doesn't have 208 parcellations..."
        echo "This could mean you've entered the wrong image or the parcellation is incorrect"
        echo "The script will still run but the cortical ROI may be wrong" 
        echo "CHECK YOUR GIF PARCELLATION IMAGE"
        echo ----------
        exit
    fi
fi

#If base ROI directory is not set, set it as the output directory
if [ -z ${base_roi_dir} ]; then 
    base_roi_dir=${out_dir}/roi
fi 

## Change stuff below 
# Add bundle name to roi_dir
roi_dir=${base_roi_dir}/AF
mask_dir=${base_roi_dir}/masks

# Create folders if needed
if [ ! -d ${out_dir} ] ; then mkdir -p ${out_dir} ; fi
if [ ! -d ${roi_dir} ] ; then mkdir -p ${roi_dir} ; fi
if [ ! -d ${mask_dir} ] ; then mkdir -p ${mask_dir} ; fi

#If user specifies niftyReg instead of easyReg then use this:
if [ ${niftyReg} = "true" ]; then
    echo "Registering MNI masks to subjects T1 using NiftyReg..." 
    #Make output directory
    if [ ! -d ${base_roi_dir}/niftiReg/ ]; then mkdir -p ${base_roi_dir}/niftiReg/; fi 
    #Align T1 to MNI (Affine) 
    if [ ! -f ${base_roi_dir}/niftiReg/T1_to_MNI_affine.mat ]; then 
        reg_aladin -ref ${FSLDIR}/data/standard/MNI152_T1_1mm -flo ${T1} -aff ${base_roi_dir}/niftiReg/T1_to_MNI_affine.mat
    fi 
    #Invert that transformation so its MNI to T1
    if [ ! -f ${base_roi_dir}/niftiReg/MNI_to_T1_affine.mat ]; then 
        convert_xfm -omat ${base_roi_dir}/niftiReg/MNI_to_T1_affine.mat -inverse ${base_roi_dir}/niftiReg/T1_to_MNI_affine.mat 
    fi 
    #Perform non-linear registration of MNI to T1 using Affine initially
    if [ ! -f ${base_roi_dir}/niftiReg/MNI_to_T1_f3d.nii.gz ]; then 
        reg_f3d -ref ${T1} -flo ${FSLDIR}/data/standard/MNI152_T1_1mm.nii.gz -aff ${base_roi_dir}/niftiReg/MNI_to_T1_affine.mat -cpp ${base_roi_dir}/niftiReg/MNI_to_T1_cpp.nii.gz -res ${base_roi_dir}/niftiReg/MNI_to_T1_f3d.nii.gz
    fi
    #Move Anatomical Priors across to dMRI space
    if [ ! -f ${mask_dir}/left_AFae_mask_dil.nii.gz ]; then 
        reg_resample -flo ${anatomical_priors}/left_AFae_mask_dil.nii.gz -ref ${T1} -trans ${base_roi_dir}/niftiReg/MNI_to_T1_cpp.nii.gz -res ${mask_dir}/left_AFae_mask_dil.nii.gz
    fi 
    if [ ! -f ${mask_dir}/left_AFve_mask_dil.nii.gz ]; then 
        reg_resample -flo ${anatomical_priors}/left_AFve_mask_dil.nii.gz -ref ${T1} -trans ${base_roi_dir}/niftiReg/MNI_to_T1_cpp.nii.gz -res ${mask_dir}/left_AFve_mask_dil.nii.gz
    fi 
    if [ ! -f ${mask_dir}/left_AFle_mask_dil.nii.gz ]; then 
        reg_resample -flo ${anatomical_priors}/left_AFle_mask_dil.nii.gz -ref ${T1} -trans ${base_roi_dir}/niftiReg/MNI_to_T1_cpp.nii.gz -res ${mask_dir}/left_AFle_mask_dil.nii.gz
    fi 
    if [ ! -f ${mask_dir}/right_AFae_mask_dil.nii.gz ]; then 
        reg_resample -flo ${anatomical_priors}/right_AFae_mask_dil.nii.gz -ref ${T1} -trans ${base_roi_dir}/niftiReg/MNI_to_T1_cpp.nii.gz -res ${mask_dir}/right_AFae_mask_dil.nii.gz
    fi 
    if [ ! -f ${mask_dir}/right_AFve_mask_dil.nii.gz ]; then 
        reg_resample -flo ${anatomical_priors}/right_AFve_mask_dil.nii.gz -ref ${T1} -trans ${base_roi_dir}/niftiReg/MNI_to_T1_cpp.nii.gz -res ${mask_dir}/right_AFve_mask_dil.nii.gz
    fi 
    if [ ! -f ${mask_dir}/right_AFle_mask_dil.nii.gz ]; then 
        reg_resample -flo ${anatomical_priors}/right_AFle_mask_dil.nii.gz -ref ${T1} -trans ${base_roi_dir}/niftiReg/MNI_to_T1_cpp.nii.gz -res ${mask_dir}/right_AFle_mask_dil.nii.gz
    fi
else 
    echo "Registering MNI masks to subjects T1 using EasyReg..." 
    #Make output directory
    if [ ! -d ${base_roi_dir}/easyReg/ ]; then mkdir -p ${base_roi_dir}/easyReg/; fi 
    #Use synthSeg to parcellate the T1 image 
    if [ ! -f ${base_roi_dir}/easyReg/T1_synthseg.nii.gz ]; then 
      mri_synthseg --i ${T1} --o ${base_roi_dir}/easyReg/T1_synthseg.nii.gz --robust --parc --threads ${threads}
    fi 
    #Perform easyReg registration
    if [ ! -f ${base_roi_dir}/easyReg/MNI_to_T1_fwd.nii.gz ]; then 
      mri_easyreg --flo ${FSLDIR}/data/standard/MNI152_T1_1mm.nii.gz --ref ${T1} --flo_seg ${anatomical_priors}/MNI152_T1_1mm_synthSeg.nii.gz --ref_seg ${base_roi_dir}/easyReg/T1_synthseg.nii.gz --flo_reg ${base_roi_dir}/easyReg/MNI_to_T1.nii.gz --fwd_field ${base_roi_dir}/easyReg/MNI_to_T1_fwd.nii.gz --bak_field ${base_roi_dir}/easyReg/MNI_to_T1_bak.nii.gz --threads ${threads}
    fi
    #Move across the MNI masks to patient space using easyWarp  
    if [ ! -f ${mask_dir}/left_AFae_mask_dil.nii.gz ]; then 
        mri_easywarp --i ${anatomical_priors}/left_AFae_mask_dil.nii.gz --o ${mask_dir}/left_AFae_mask_dil.nii.gz --field ${base_roi_dir}/easyReg/MNI_to_T1_fwd.nii.gz --threads ${threads}
    fi 
    if [ ! -f ${mask_dir}/left_AFve_mask_dil.nii.gz ]; then 
        mri_easywarp --i ${anatomical_priors}/left_AFve_mask_dil.nii.gz --o ${mask_dir}/left_AFve_mask_dil.nii.gz --field ${base_roi_dir}/easyReg/MNI_to_T1_fwd.nii.gz --threads ${threads}
    fi 
    if [ ! -f ${mask_dir}/left_AFle_mask_dil.nii.gz ]; then 
        mri_easywarp --i ${anatomical_priors}/left_AFle_mask_dil.nii.gz --o ${mask_dir}/left_AFle_mask_dil.nii.gz --field ${base_roi_dir}/easyReg/MNI_to_T1_fwd.nii.gz --threads ${threads}
    fi 
    if [ ! -f ${mask_dir}/right_AFae_mask_dil.nii.gz ]; then 
        mri_easywarp --i ${anatomical_priors}/right_AFae_mask_dil.nii.gz --o ${mask_dir}/right_AFae_mask_dil.nii.gz --field ${base_roi_dir}/easyReg/MNI_to_T1_fwd.nii.gz --threads ${threads}
    fi 
    if [ ! -f ${mask_dir}/right_AFve_mask_dil.nii.gz ]; then 
        mri_easywarp --i ${anatomical_priors}/right_AFve_mask_dil.nii.gz --o ${mask_dir}/right_AFve_mask_dil.nii.gz --field ${base_roi_dir}/easyReg/MNI_to_T1_fwd.nii.gz --threads ${threads}
    fi 
    if [ ! -f ${mask_dir}/right_AFle_mask_dil.nii.gz ]; then 
        mri_easywarp --i ${anatomical_priors}/right_AFle_mask_dil.nii.gz --o ${mask_dir}/right_AFle_mask_dil.nii.gz --field ${base_roi_dir}/easyReg/MNI_to_T1_fwd.nii.gz --threads ${threads} 
    fi 
fi 

echo "Extracting the cortical ROIs from the GIF parcellation"
#ROI Extraction 
#   Left Hemisphere Seed
if [ ! -f ${roi_dir}/left_AF_seed.nii.gz ]; then
    #Extact MFG regions (left hemisphere)
    ${ROIsplit} --parc ${gif_parc} --label 144 --sections 3 --out ${roi_dir}/left_MFG_split.nii.gz
    mrcalc ${roi_dir}/left_MFG_split.nii.gz 2 -eq ${roi_dir}/left_MFG_DLPFC.nii.gz
    mrcalc ${roi_dir}/left_MFG_split.nii.gz 1 -eq ${roi_dir}/left_MFG_dPMC.nii.gz
    #Extract Precentral gyrus regions 
    ${ROIsplit} --parc ${gif_parc} --label 184 --sections 3 --out ${roi_dir}/left_PcG_split.nii.gz
    mrcalc ${roi_dir}/left_PcG_split.nii.gz 3 -eq ${roi_dir}/left_PcG_ven.nii.gz
    mrcalc ${roi_dir}/left_PcG_split.nii.gz 2 -eq ${roi_dir}/left_PcG_mid.nii.gz
    #Extract IFG regions 
    mrcalc ${gif_parc} 164 -eq ${roi_dir}/left_pars_op.nii.gz
    mrcalc ${gif_parc} 206 -eq ${roi_dir}/left_pars_tri.nii.gz
    #Combine them
    mrcalc ${roi_dir}/left_MFG_DLPFC.nii.gz \
        ${roi_dir}/left_MFG_dPMC.nii.gz -add \
        ${roi_dir}/left_PcG_ven.nii.gz -add \
        ${roi_dir}/left_PcG_mid.nii.gz -add \
        ${roi_dir}/left_pars_op.nii.gz -add \
        ${roi_dir}/left_pars_tri.nii.gz -add \
        ${roi_dir}/left_AF_seed.nii.gz tst.nii.gz
fi
#   Right Hemisphere Seed
if [ ! -f ${roi_dir}/right_AF_seed.nii.gz ]; then
    # Extract MFG regions (right hemisphere)
    ${ROIsplit} --parc ${gif_parc} --label 143 --sections 3 --out ${roi_dir}/right_MFG_split.nii.gz
    mrcalc ${roi_dir}/right_MFG_split.nii.gz 2 -eq ${roi_dir}/right_MFG_dPMC.nii.gz
    mrcalc ${roi_dir}/right_MFG_split.nii.gz 3 -eq ${roi_dir}/right_MFG_DLPFC.nii.gz
    # Extract Precentral gyrus regions (right hemisphere)
    ${ROIsplit} --parc ${gif_parc} --label 183 --sections 3 --out ${roi_dir}/right_PcG_split.nii.gz
    mrcalc ${roi_dir}/right_PcG_split.nii.gz 3 -eq ${roi_dir}/right_PcG_ven.nii.gz
    mrcalc ${roi_dir}/right_PcG_split.nii.gz 2 -eq ${roi_dir}/right_PcG_mid.nii.gz
    # Extract IFG regions (right hemisphere)
    mrcalc ${gif_parc} 163 -eq ${roi_dir}/right_pars_op.nii.gz
    mrcalc ${gif_parc} 205 -eq ${roi_dir}/right_pars_tri.nii.gz
    # Combine all extracted regions into a single seed mask
    mrcalc ${roi_dir}/right_MFG_dPMC.nii.gz \
        ${roi_dir}/right_MFG_DLPFC.nii.gz -add \
        ${roi_dir}/right_PcG_ven.nii.gz -add \
        ${roi_dir}/right_PcG_mid.nii.gz -add \
        ${roi_dir}/right_pars_op.nii.gz -add \
        ${roi_dir}/right_pars_tri.nii.gz -add \
        ${roi_dir}/right_AF_seed.nii.gz
fi


# Termination regions,,,
# Left Auditory Encoding
if [ ! -f ${roi_dir}/left_AFae_termination.nii.gz ]; then
    ${ROIsplit} --parc ${gif_parc} --label 202 --sections 3 --out ${roi_dir}/left_STG_split.nii.gz
    mrcalc ${roi_dir}/left_STG_split.nii.gz 2 -eq ${roi_dir}/left_STGm.nii.gz
    mrcalc ${gif_parc} 156 -eq ${roi_dir}/left_MTG.nii.gz
    mrcalc ${roi_dir}/left_STGm.nii.gz ${roi_dir}/left_MTG.nii.gz -add ${roi_dir}/left_AFae_termination.nii.gz
fi

# Right Auditory Encoding
if [ ! -f ${roi_dir}/right_AFae_termination.nii.gz ]; then
    ${ROIsplit} --parc ${gif_parc} --label 201 --sections 3 --out ${roi_dir}/right_STG_split.nii.gz
    mrcalc ${roi_dir}/right_STG_split.nii.gz 3 -eq ${roi_dir}/right_STGm.nii.gz
    mrcalc ${gif_parc} 155 -eq ${roi_dir}/right_MTG.nii.gz
    mrcalc ${roi_dir}/right_STGm.nii.gz ${roi_dir}/right_MTG.nii.gz -add ${roi_dir}/right_AFae_termination.nii.gz
fi

# Left Visual Encoding
if [ ! -f ${roi_dir}/left_AFve_termination.nii.gz ]; then
    ${ROIsplit} --parc ${gif_parc} --label 134 --sections 2 --out ${roi_dir}/left_ITG_split.nii.gz
    mrcalc ${roi_dir}/left_ITG_split.nii.gz 1 -eq ${roi_dir}/left_ITGp.nii.gz
    ${ROIsplit} --parc ${gif_parc} --label 124 --sections 2 --out ${roi_dir}/left_FG_split.nii.gz
    mrcalc ${roi_dir}/left_FG_split.nii.gz 1 -eq ${roi_dir}/left_FGp.nii.gz
    mrcalc ${roi_dir}/left_ITGp.nii.gz ${roi_dir}/left_FGp.nii.gz -add ${roi_dir}/left_AFve_termination.nii.gz
fi

# Right Visual Encoding
if [ ! -f ${roi_dir}/right_AFve_termination.nii.gz ]; then
    ${ROIsplit} --parc ${gif_parc} --label 133 --sections 2 --out ${roi_dir}/right_ITG_split.nii.gz
    mrcalc ${roi_dir}/right_ITG_split.nii.gz 2 -eq ${roi_dir}/right_ITGp.nii.gz
    ${ROIsplit} --parc ${gif_parc} --label 123 --sections 2 --out ${roi_dir}/right_FG_split.nii.gz
    mrcalc ${roi_dir}/right_FG_split.nii.gz 2 -eq ${roi_dir}/right_FGp.nii.gz
    mrcalc ${roi_dir}/right_ITGp.nii.gz ${roi_dir}/right_FGp.nii.gz -add ${roi_dir}/right_AFve_termination.nii.gz
fi

# Left Lexical Encoding
if [ ! -f ${roi_dir}/left_AFle_termination.nii.gz ]; then
    ${ROIsplit} --parc ${gif_parc} --label 134 --sections 2 --out ${roi_dir}/left_ITG_split.nii.gz
    mrcalc ${roi_dir}/left_ITG_split.nii.gz 2 -eq ${roi_dir}/left_ITGa.nii.gz
    ${ROIsplit} --parc ${gif_parc} --label 124 --sections 2 --out ${roi_dir}/left_FG_split.nii.gz
    mrcalc ${roi_dir}/left_FG_split.nii.gz 2 -eq ${roi_dir}/left_FGa.nii.gz
    mrcalc ${roi_dir}/left_ITGa.nii.gz ${roi_dir}/left_FGa.nii.gz -add ${roi_dir}/left_AFle_termination.nii.gz
fi

# Right Lexical Encoding
if [ ! -f ${roi_dir}/right_AFle_termination.nii.gz ]; then
    ${ROIsplit} --parc ${gif_parc} --label 133 --sections 2 --out ${roi_dir}/right_ITG_split.nii.gz
    mrcalc ${roi_dir}/right_ITG_split.nii.gz 1 -eq ${roi_dir}/right_ITGa.nii.gz
    ${ROIsplit} --parc ${gif_parc} --label 123 --sections 2 --out ${roi_dir}/right_FG_split.nii.gz
    mrcalc ${roi_dir}/right_FG_split.nii.gz 1 -eq ${roi_dir}/right_FGa.nii.gz
    mrcalc ${roi_dir}/right_ITGa.nii.gz ${roi_dir}/right_FGa.nii.gz -add ${roi_dir}/right_AFle_termination.nii.gz
fi

echo "Dilating the cortical ROIs into the 5tt white matter and 7T mask"
if [ ! -f ${roi_dir}/left_AFae_seed_dil.nii.gz ]; then 
    ${dilation} --hsvs_5tt ${fivett} --mask ${mask_dir}/left_AFae_mask_dil.nii.gz --in ${roi_dir}/left_AF_seed.nii.gz --out ${roi_dir}/left_AFae_seed_dil.nii.gz
fi
if [ ! -f ${roi_dir}/left_AFve_seed_dil.nii.gz ]; then 
    ${dilation} --hsvs_5tt ${fivett} --mask ${mask_dir}/left_AFve_mask_dil.nii.gz --in ${roi_dir}/left_AF_seed.nii.gz --out ${roi_dir}/left_AFve_seed_dil.nii.gz
fi
if [ ! -f ${roi_dir}/left_AFle_seed_dil.nii.gz ]; then 
    ${dilation} --hsvs_5tt ${fivett} --mask ${mask_dir}/left_AFle_mask_dil.nii.gz --in ${roi_dir}/left_AF_seed.nii.gz --out ${roi_dir}/left_AFle_seed_dil.nii.gz
fi
if [ ! -f ${roi_dir}/right_AFae_seed_dil.nii.gz ]; then 
    ${dilation} --hsvs_5tt ${fivett} --mask ${mask_dir}/right_AFae_mask_dil.nii.gz --in ${roi_dir}/right_AF_seed.nii.gz --out ${roi_dir}/right_AFae_seed_dil.nii.gz
fi
if [ ! -f ${roi_dir}/right_AFve_seed_dil.nii.gz ]; then 
    ${dilation} --hsvs_5tt ${fivett} --mask ${mask_dir}/right_AFve_mask_dil.nii.gz --in ${roi_dir}/right_AF_seed.nii.gz --out ${roi_dir}/right_AFve_seed_dil.nii.gz
fi
if [ ! -f ${roi_dir}/right_AFle_seed_dil.nii.gz ]; then 
    ${dilation} --hsvs_5tt ${fivett} --mask ${mask_dir}/right_AFle_mask_dil.nii.gz --in ${roi_dir}/right_AF_seed.nii.gz --out ${roi_dir}/right_AFle_seed_dil.nii.gz
fi
if [ ! -f ${roi_dir}/right_AFae_termination_dil.nii.gz ]; then 
    ${dilation} --hsvs_5tt ${fivett} --mask ${mask_dir}/right_AFae_mask_dil.nii.gz --in ${roi_dir}/right_AFae_termination.nii.gz --out ${roi_dir}/right_AFae_termination_dil.nii.gz
fi 
if [ ! -f ${roi_dir}/left_AFae_termination_dil.nii.gz ]; then 
    ${dilation} --hsvs_5tt ${fivett} --mask ${mask_dir}/left_AFae_mask_dil.nii.gz --in ${roi_dir}/left_AFae_termination.nii.gz --out ${roi_dir}/left_AFae_termination_dil.nii.gz
fi 
if [ ! -f ${roi_dir}/left_AFve_termination_dil.nii.gz ]; then 
    ${dilation} --hsvs_5tt ${fivett} --mask ${mask_dir}/left_AFve_mask_dil.nii.gz --in ${roi_dir}/left_AFve_termination.nii.gz --out ${roi_dir}/left_AFve_termination_dil.nii.gz
fi 
if [ ! -f ${roi_dir}/right_AFve_termination_dil.nii.gz ]; then 
    ${dilation} --hsvs_5tt ${fivett} --mask ${mask_dir}/right_AFve_mask_dil.nii.gz --in ${roi_dir}/right_AFve_termination.nii.gz --out ${roi_dir}/right_AFve_termination_dil.nii.gz
fi 
if [ ! -f ${roi_dir}/left_AFle_termination_dil.nii.gz ]; then 
    ${dilation} --hsvs_5tt ${fivett} --mask ${mask_dir}/left_AFle_mask_dil.nii.gz --in ${roi_dir}/left_AFle_termination.nii.gz --out ${roi_dir}/left_AFle_termination_dil.nii.gz
fi 
if [ ! -f ${roi_dir}/right_AFle_termination_dil.nii.gz ]; then 
    ${dilation} --hsvs_5tt ${fivett} --mask ${mask_dir}/right_AFle_mask_dil.nii.gz --in ${roi_dir}/right_AFle_termination.nii.gz --out ${roi_dir}/right_AFle_termination_dil.nii.gz
fi 

echo "Performing tractography"
#Tractography Left AF Auditory Encoding
if [ ! -f ${out_dir}/left_AFae.tck ]; then 
    tckgen ${FOD} -algorithm ${algorithm} -act ${fivett} -seed_image ${roi_dir}/left_AFae_seed_dil.nii.gz -include ${roi_dir}/left_AFae_termination_dil.nii.gz -maxlength 300 ${out_dir}/left_AFae_prob_SW.tck -seed_unidirectional  -mask ${mask_dir}/left_AFae_mask_dil.nii.gz ${options} -seeds 25000000 -select 10k
    tckgen ${FOD} -algorithm ${algorithm} -act ${fivett} -seed_image ${roi_dir}/left_AFae_termination_dil.nii.gz -include ${roi_dir}/left_AFae_seed_dil.nii.gz -maxlength 300 ${out_dir}/left_AFae_prob_WS.tck -seed_unidirectional  -mask ${mask_dir}/left_AFae_mask_dil.nii.gz ${options} -seeds 25000000 -select 10k
    tckedit ${out_dir}/left_AFae_prob_SW.tck ${out_dir}/left_AFae_prob_WS.tck ${out_dir}/left_AFae_prob_unpruned.tck
    tckedit ${out_dir}/left_AFae_prob_unpruned.tck -include ${roi_dir}/left_AFae_seed_dil.nii.gz -include ${roi_dir}/left_AFae_termination_dil.nii.gz ${out_dir}/left_AFae_prob_unpruned_ends.tck -ends_only
    ${pruning} -in ${out_dir}/left_AFae_prob_unpruned_ends.tck -templ_im ${T1} -out ${out_dir}/left_AFae.tck -thr 0.05
    if [ -f ${out_dir}/left_AFae.tck ]; then 
        rm -r ${out_dir}/left_AFae_prob_SW.tck ${out_dir}/left_AFae_prob_WS.tck ${out_dir}/left_AFae_prob_unpruned.tck ${out_dir}/left_AFae_prob_unpruned_ends.tck
    fi 
fi
#Tractography: Left AF Visual Encoding
if [ ! -f ${out_dir}/left_AFve.tck ]; then 
    tckgen ${FOD} -algorithm ${algorithm} -act ${fivett} -seed_image ${roi_dir}/left_AFve_seed_dil.nii.gz -include ${roi_dir}/left_AFve_termination_dil.nii.gz -maxlength 300 ${out_dir}/left_AFve_prob_SW.tck -seed_unidirectional  -mask ${mask_dir}/left_AFve_mask_dil.nii.gz ${options} -seeds 25000000 -select 10k
    tckgen ${FOD} -algorithm ${algorithm} -act ${fivett} -seed_image ${roi_dir}/left_AFve_termination_dil.nii.gz -include ${roi_dir}/left_AFve_seed_dil.nii.gz -maxlength 300 ${out_dir}/left_AFve_prob_WS.tck -seed_unidirectional  -mask ${mask_dir}/left_AFve_mask_dil.nii.gz ${options} -seeds 25000000 -select 10k
    tckedit ${out_dir}/left_AFve_prob_SW.tck ${out_dir}/left_AFve_prob_WS.tck ${out_dir}/left_AFve_prob_unpruned.tck
    tckedit ${out_dir}/left_AFve_prob_unpruned.tck -include ${roi_dir}/left_AFve_seed_dil.nii.gz -include ${roi_dir}/left_AFve_termination_dil.nii.gz ${out_dir}/left_AFve_prob_unpruned_ends.tck -ends_only
    ${pruning} -in ${out_dir}/left_AFve_prob_unpruned_ends.tck -templ_im ${T1} -out ${out_dir}/left_AFve.tck -thr 0.05    
    if [ -f ${out_dir}/left_AFve.tck ]; then 
        rm -r ${out_dir}/left_AFve_prob_SW.tck ${out_dir}/left_AFve_prob_WS.tck ${out_dir}/left_AFve_prob_unpruned.tck ${out_dir}/left_AFve_prob_unpruned_ends.tck
    fi 
fi
#Tractography: Left AF Lexical Encoding
if [ ! -f ${out_dir}/left_AFle.tck ]; then 
    tckgen ${FOD} -algorithm ${algorithm} -act ${fivett} -seed_image ${roi_dir}/left_AFle_seed_dil.nii.gz -include ${roi_dir}/left_AFle_termination_dil.nii.gz -maxlength 300 ${out_dir}/left_AFle_prob_SW.tck -seed_unidirectional  -mask ${mask_dir}/left_AFle_mask_dil.nii.gz ${options} -seeds 25000000 -select 10k
    tckgen ${FOD} -algorithm ${algorithm} -act ${fivett} -seed_image ${roi_dir}/left_AFle_termination_dil.nii.gz -include ${roi_dir}/left_AFle_seed_dil.nii.gz -maxlength 300 ${out_dir}/left_AFle_prob_WS.tck -seed_unidirectional  -mask ${mask_dir}/left_AFle_mask_dil.nii.gz ${options} -seeds 25000000 -select 10k
    tckedit ${out_dir}/left_AFle_prob_SW.tck ${out_dir}/left_AFle_prob_WS.tck ${out_dir}/left_AFle_prob_unpruned.tck
    tckedit ${out_dir}/left_AFle_prob_unpruned.tck -include ${roi_dir}/left_AFle_seed_dil.nii.gz -include ${roi_dir}/left_AFle_termination_dil.nii.gz ${out_dir}/left_AFle_prob_unpruned_ends.tck -ends_only
    ${pruning} -in ${out_dir}/left_AFle_prob_unpruned_ends.tck -templ_im ${T1} -out ${out_dir}/left_AFle.tck -thr 0.05
    if [ -f ${out_dir}/left_AFle.tck ]; then 
        rm -r ${out_dir}/left_AFle_prob_SW.tck ${out_dir}/left_AFle_prob_WS.tck ${out_dir}/left_AFle_prob_unpruned.tck ${out_dir}/left_AFle_prob_unpruned_ends.tck
    fi 
fi
#Tractography: Left AF Auditory Encoding
if [ ! -f ${out_dir}/right_AFae.tck ]; then 
    tckgen ${FOD} -algorithm ${algorithm} -act ${fivett} -seed_image ${roi_dir}/right_AFae_seed_dil.nii.gz -include ${roi_dir}/right_AFae_termination_dil.nii.gz -maxlength 300 ${out_dir}/right_AFae_prob_SW.tck -seed_unidirectional  -mask ${mask_dir}/right_AFae_mask_dil.nii.gz  ${options} -seeds 25000000 -select 10k
    tckgen ${FOD} -algorithm ${algorithm} -act ${fivett} -seed_image ${roi_dir}/right_AFae_termination_dil.nii.gz -include ${roi_dir}/right_AFae_seed_dil.nii.gz -maxlength 300 ${out_dir}/right_AFae_prob_WS.tck -seed_unidirectional  -mask ${mask_dir}/right_AFae_mask_dil.nii.gz  ${options} -seeds 25000000 -select 10k
    tckedit ${out_dir}/right_AFae_prob_SW.tck ${out_dir}/right_AFae_prob_WS.tck ${out_dir}/right_AFae_prob_unpruned.tck
    tckedit ${out_dir}/right_AFae_prob_unpruned.tck -include ${roi_dir}/right_AFae_seed_dil.nii.gz -include ${roi_dir}/right_AFae_termination_dil.nii.gz ${out_dir}/right_AFae_prob_unpruned_ends.tck -ends_only
    ${pruning} -in ${out_dir}/right_AFae_prob_unpruned_ends.tck -templ_im ${T1} -out ${out_dir}/right_AFae.tck -thr 0.05
    if [ -f ${out_dir}/right_AFae.tck ]; then 
        rm -r ${out_dir}/right_AFae_prob_SW.tck ${out_dir}/right_AFae_prob_WS.tck ${out_dir}/right_AFae_prob_unpruned.tck ${out_dir}/right_AFae_prob_unpruned_ends.tck
    fi 
fi
#Tractography: Right AF Visual Encoding
if [ ! -f ${out_dir}/right_AFve.tck ]; then 
    tckgen ${FOD} -algorithm ${algorithm} -act ${fivett} -seed_image ${roi_dir}/right_AFve_seed_dil.nii.gz -include ${roi_dir}/right_AFve_termination_dil.nii.gz -maxlength 300 ${out_dir}/right_AFve_prob_SW.tck -seed_unidirectional  -mask ${mask_dir}/right_AFve_mask_dil.nii.gz ${options} -seeds 25000000 -select 10k
    tckgen ${FOD} -algorithm ${algorithm} -act ${fivett} -seed_image ${roi_dir}/right_AFve_termination_dil.nii.gz -include ${roi_dir}/right_AFve_seed_dil.nii.gz -maxlength 300 ${out_dir}/right_AFve_prob_WS.tck -seed_unidirectional  -mask ${mask_dir}/right_AFve_mask_dil.nii.gz ${options} -seeds 25000000 -select 10k
    tckedit ${out_dir}/right_AFve_prob_SW.tck ${out_dir}/right_AFve_prob_WS.tck ${out_dir}/right_AFve_prob_unpruned.tck
    tckedit ${out_dir}/right_AFve_prob_unpruned.tck -include ${roi_dir}/right_AFve_seed_dil.nii.gz -include ${roi_dir}/right_AFve_termination_dil.nii.gz ${out_dir}/right_AFve_prob_unpruned_ends.tck -ends_only
    ${pruning} -in ${out_dir}/right_AFve_prob_unpruned_ends.tck -templ_im ${T1} -out ${out_dir}/right_AFve.tck -thr 0.05
    if [ -f ${out_dir}/right_AFve.tck ]; then 
        rm -r ${out_dir}/right_AFve_prob_SW.tck ${out_dir}/right_AFve_prob_WS.tck ${out_dir}/right_AFve_prob_unpruned.tck ${out_dir}/right_AFve_prob_unpruned_ends.tck
    fi 
fi
#Tractography: Right AF Lexical Encoding
if [ ! -f ${out_dir}/right_AFle.tck ]; then 
    tckgen ${FOD} -algorithm ${algorithm} -act ${fivett} -seed_image ${roi_dir}/right_AFle_seed_dil.nii.gz -include ${roi_dir}/right_AFle_termination_dil.nii.gz -maxlength 300 ${out_dir}/right_AFle_prob_SW.tck -seed_unidirectional  -mask ${mask_dir}/right_AFle_mask_dil.nii.gz ${options} -seeds 25000000 -select 10k
    tckgen ${FOD} -algorithm ${algorithm} -act ${fivett} -seed_image ${roi_dir}/right_AFle_termination_dil.nii.gz -include ${roi_dir}/right_AFle_seed_dil.nii.gz -maxlength 300 ${out_dir}/right_AFle_prob_WS.tck -seed_unidirectional  -mask ${mask_dir}/right_AFle_mask_dil.nii.gz ${options} -seeds 25000000 -select 10k
    tckedit ${out_dir}/right_AFle_prob_SW.tck ${out_dir}/right_AFle_prob_WS.tck ${out_dir}/right_AFle_prob_unpruned.tck
    tckedit ${out_dir}/right_AFle_prob_unpruned.tck -include ${roi_dir}/right_AFle_seed_dil.nii.gz -include ${roi_dir}/right_AFle_termination_dil.nii.gz ${out_dir}/right_AFle_prob_unpruned_ends.tck -ends_only
    ${pruning} -in ${out_dir}/right_AFle_prob_unpruned_ends.tck -templ_im ${T1} -out ${out_dir}/right_AFle.tck -thr 0.05
    if [ -f ${out_dir}/right_AFle.tck ]; then 
        rm -r ${out_dir}/right_AFle_prob_SW.tck ${out_dir}/right_AFle_prob_WS.tck ${out_dir}/right_AFle_prob_unpruned.tck ${out_dir}/right_AFle_prob_unpruned_ends.tck
    fi 
fi