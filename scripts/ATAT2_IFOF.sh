#!/bin/bash

# Inferior fronto-occipital Fasciculus AT-ATv2
#   Based off 7T tractography
#
# REQUIREMENTS:
#       FSL path in shell
#       MRtrix3 path in shell
#
# Created by Lawrence Binding 15/08/2022
#     Updated by Lawrence Binding 19/08/2025: Updated for modern formatting

# Get script name
script_name=`basename $0`

# Get script location
main_dir="$(dirname "$(realpath "$BASH_SOURCE")")/.."
script_path="$(dirname "$(realpath "$BASH_SOURCE")")"
anatomical_priors=${main_dir}/anatomical_priors/

# Assign scripts to variables
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
      # Set gif parcellation
      let i=$i+1
      gif_parc=${args[i]}
    elif ( [ ${args[i]} = "-T1" ] || [ ${args[i]} = "-t1" ] ) ; then
      # Set T1 image
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
      # Set niftyReg flag
      let i=$i+1
      niftyReg="true"
    elif ( [ ${args[i]} = "-alg" ] ) ; then
      # Set algorithm
      let i=$i+1
      algorithm=${args[i]}
    elif ( [ ${args[i]} = "-threads" ] ) ; then
      # Set number of threads for easyReg to use 
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
if [ ! -f ${T1} ]; then
    echo ----------
    echo "T1 image does not exist, please check inputs"
    echo ----------
    exit
fi
#Check if the FOD image exists
if [ ! -f ${FOD} ]; then
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

# Add bundle name to roi_dir
roi_dir=${base_roi_dir}/IFOF
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
    #Align brain T1 to MNI brain
    if [ ! -f ${base_roi_dir}/niftiReg/T1_to_MNI_affine.mat ]; then
        reg_aladin -ref ${FSLDIR}/data/standard/MNI152_T1_1mm -flo ${T1} -aff ${base_roi_dir}/niftiReg/T1_to_MNI_affine.mat
    fi
    #Invert that transformation so its MNI to T1
    if [ ! -f ${base_roi_dir}/niftiReg/MNI_to_T1_affine.mat ]; then
        convert_xfm -omat ${base_roi_dir}/niftiReg/MNI_to_T1_affine.mat -inverse ${base_roi_dir}/niftiReg/T1_to_MNI_affine.mat
    fi
    #Perform non-linear registration
    if [ ! -f ${base_roi_dir}/niftiReg/MNI_to_T1_f3d.nii.gz ]; then
        reg_f3d -ref ${T1} -flo ${FSLDIR}/data/standard/MNI152_T1_1mm.nii.gz -aff ${base_roi_dir}/niftiReg/MNI_to_T1_affine.mat -cpp ${base_roi_dir}/niftiReg/MNI_to_T1_cpp.nii.gz -res ${base_roi_dir}/niftiReg/MNI_to_T1_f3d.nii.gz
    fi
    if [ ! -f ${mask_dir}/left_IFOFdm_mask_dil.nii.gz ]; then
        reg_resample -flo ${anatomical_priors}/left_IFOFdm_mask_dil.nii.gz -ref ${T1} -trans ${base_roi_dir}/niftiReg/MNI_to_T1_cpp.nii.gz -res ${mask_dir}/left_IFOFdm_mask_dil.nii.gz
    fi
    if [ ! -f ${mask_dir}/right_IFOFdm_mask_dil.nii.gz ]; then
        reg_resample -flo ${anatomical_priors}/right_IFOFdm_mask_dil.nii.gz -ref ${T1} -trans ${base_roi_dir}/niftiReg/MNI_to_T1_cpp.nii.gz -res ${mask_dir}/right_IFOFdm_mask_dil.nii.gz
    fi
    if [ ! -f ${mask_dir}/left_IFOFvm_mask_dil.nii.gz ]; then
        reg_resample -flo ${anatomical_priors}/left_IFOFvm_mask_dil.nii.gz -ref ${T1} -trans ${base_roi_dir}/niftiReg/MNI_to_T1_cpp.nii.gz -res ${mask_dir}/left_IFOFvm_mask_dil.nii.gz
    fi
    if [ ! -f ${mask_dir}/right_IFOFvm_mask_dil.nii.gz ]; then
        reg_resample -flo ${anatomical_priors}/right_IFOFvm_mask_dil.nii.gz -ref ${T1} -trans ${base_roi_dir}/niftiReg/MNI_to_T1_cpp.nii.gz -res ${mask_dir}/right_IFOFvm_mask_dil.nii.gz
    fi
    if [ ! -f ${mask_dir}/left_IFOFvl_mask_dil.nii.gz ]; then
        reg_resample -flo ${anatomical_priors}/left_IFOFvl_mask_dil.nii.gz -ref ${T1} -trans ${base_roi_dir}/niftiReg/MNI_to_T1_cpp.nii.gz -res ${mask_dir}/left_IFOFvl_mask_dil.nii.gz
    fi
    if [ ! -f ${mask_dir}/right_IFOFvl_mask_dil.nii.gz ]; then
        reg_resample -flo ${anatomical_priors}/right_IFOFvl_mask_dil.nii.gz -ref ${T1} -trans ${base_roi_dir}/niftiReg/MNI_to_T1_cpp.nii.gz -res ${mask_dir}/right_IFOFvl_mask_dil.nii.gz
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
        mri_easyreg --flo ${FSLDIR}/data/standard/MNI152_T1_1mm.nii.gz --ref ${T1} --flo_seg ${anatomical_priors}/MNI152_T1_1mm_synthSeg.nii.gz --ref_seg ${base_roi_dir}/easyReg/T1_synthseg.nii.gz --flo_reg ${base_roi_dir}/easyReg/MNI_to_T1.nii.gz --fwd_field ${base_roi_dir}/easyReg/MNI_to_T1_fwd.nii.gz --threads ${threads}
    fi
    #Move across the MNI masks to patient space- easyWarp
    if [ ! -f ${mask_dir}/left_IFOFdm_mask_dil.nii.gz ]; then
        mri_easywarp --i ${anatomical_priors}/left_IFOFdm_mask_dil.nii.gz --o ${mask_dir}/left_IFOFdm_mask_dil.nii.gz --field ${base_roi_dir}/easyReg/MNI_to_T1_fwd.nii.gz --threads ${threads}
    fi
    if [ ! -f ${mask_dir}/left_IFOFvm_mask_dil.nii.gz ]; then
        mri_easywarp --i ${anatomical_priors}/left_IFOFvm_mask_dil.nii.gz --o ${mask_dir}/left_IFOFvm_mask_dil.nii.gz --field ${base_roi_dir}/easyReg/MNI_to_T1_fwd.nii.gz --threads ${threads}
    fi
    if [ ! -f ${mask_dir}/left_IFOFvl_mask_dil.nii.gz ]; then
        mri_easywarp --i ${anatomical_priors}/left_IFOFvl_mask_dil.nii.gz --o ${mask_dir}/left_IFOFvl_mask_dil.nii.gz --field ${base_roi_dir}/easyReg/MNI_to_T1_fwd.nii.gz --threads ${threads}
    fi
    if [ ! -f ${mask_dir}/right_IFOFdm_mask_dil.nii.gz ]; then
        mri_easywarp --i ${anatomical_priors}/right_IFOFdm_mask_dil.nii.gz --o ${mask_dir}/right_IFOFdm_mask_dil.nii.gz --field ${base_roi_dir}/easyReg/MNI_to_T1_fwd.nii.gz --threads ${threads}
    fi
    if [ ! -f ${mask_dir}/right_IFOFvm_mask_dil.nii.gz ]; then
        mri_easywarp --i ${anatomical_priors}/right_IFOFvm_mask_dil.nii.gz --o ${mask_dir}/right_IFOFvm_mask_dil.nii.gz --field ${base_roi_dir}/easyReg/MNI_to_T1_fwd.nii.gz --threads ${threads}
    fi
    if [ ! -f ${mask_dir}/right_IFOFvl_mask_dil.nii.gz ]; then
        mri_easywarp --i ${anatomical_priors}/right_IFOFvl_mask_dil.nii.gz --o ${mask_dir}/right_IFOFvl_mask_dil.nii.gz --field ${base_roi_dir}/easyReg/MNI_to_T1_fwd.nii.gz --threads ${threads}
    fi
fi


echo "Extracting the cortical ROIs from the GIF parcellation"
#ROI Extraction
#   Left Hemisphere
# Left VentroLateral Sub-fasciculus SEED (IFG)
if [ ! -f ${roi_dir}/left_ventroLat_seed.nii.gz ] ; then
    mrcalc ${gif_parc} 164 -eq ${roi_dir}/left_IFOF_parsOp.nii.gz
    mrcalc ${gif_parc} 166 -eq ${roi_dir}/left_IFOF_parsOrb.nii.gz
    mrcalc ${gif_parc} 206 -eq ${roi_dir}/left_IFOF_parsTri.nii.gz
    mrcalc ${roi_dir}/left_IFOF_parsOp.nii.gz \
      ${roi_dir}/left_IFOF_parsOrb.nii.gz -add \
      ${roi_dir}/left_IFOF_parsTri.nii.gz -add \
      ${roi_dir}/left_ventroLat_seed.nii.gz -force
fi
# Left DorsoMedial Sub-fasciculus SEED (MFG)
if [ ! -f ${roi_dir}/left_dorsoMed_seed.nii.gz ] ; then
    mrcalc ${gif_parc} 144 -eq ${roi_dir}/left_dorsoMed_seed.nii.gz
fi
#Left VentroMedial Sub-fasciculus SEED (Orbital)
if [ ! -f ${roi_dir}/left_ventroMed_seed.nii.gz ] ; then
    mrcalc ${gif_parc} 148 -eq ${roi_dir}/left_orbital_med.nii.gz
    mrcalc ${gif_parc} 180 -eq ${roi_dir}/left_orbital_pos.nii.gz
    mrcalc ${gif_parc} 106 -eq ${roi_dir}/left_orbital_ant.nii.gz
    mrcalc ${gif_parc} 138 -eq ${roi_dir}/left_orbital_lat.nii.gz
    mrcalc ${roi_dir}/left_orbital_med.nii.gz \
      ${roi_dir}/left_orbital_pos.nii.gz -add \
      ${roi_dir}/left_orbital_ant.nii.gz -add \
      ${roi_dir}/left_orbital_lat.nii.gz -add \
      ${roi_dir}/left_ventroMed_seed.nii.gz -force
fi
# Left VentroLateral Sub-fasciculus TERMINATION
if [ ! -f ${roi_dir}/left_ventroLat_termination.nii.gz ] ; then
    mrcalc ${gif_parc} 110 -eq ${roi_dir}/left_calcarine.nii.gz
    mrcalc ${gif_parc} 198 -eq ${roi_dir}/left_SOG.nii.gz
    mrcalc ${gif_parc} 146 -eq ${roi_dir}/left_MOG.nii.gz
    mrcalc ${gif_parc} 130 -eq ${roi_dir}/left_IOG.nii.gz
    mrcalc ${gif_parc} 136 -eq ${roi_dir}/left_lingual.nii.gz
    mrcalc ${gif_parc} 200 -eq ${roi_dir}/left_supPar.nii.gz
    mrcalc ${gif_parc} 170 -eq ${roi_dir}/left_preCun.nii.gz
    ${ROIsplit} --parc ${gif_parc} --label 124 --sections 2 --out ${roi_dir}/left_FG_split.nii.gz
    mrcalc ${roi_dir}/left_FG_split.nii.gz 1 -eq ${roi_dir}/left_FG_pos.nii.gz
    mrcalc ${gif_parc} 162 -eq ${roi_dir}/left_FGocc.nii.gz
    mrcalc ${roi_dir}/left_calcarine.nii.gz \
      ${roi_dir}/left_SOG.nii.gz -add \
      ${roi_dir}/left_FGocc.nii.gz -add \
      ${roi_dir}/left_MOG.nii.gz -add \
      ${roi_dir}/left_IOG.nii.gz -add \
      ${roi_dir}/left_lingual.nii.gz -add \
      ${roi_dir}/left_supPar.nii.gz -add \
      ${roi_dir}/left_preCun.nii.gz -add \
      ${roi_dir}/left_FG_pos.nii.gz -add \
      ${roi_dir}/left_ventroLat_termination.nii.gz -force
fi
# Left DorsoMedial Sub-fasciculus TERMINATION
if [ ! -f ${roi_dir}/left_dorsoMed_termination.nii.gz ] ; then
    mrcalc ${gif_parc} 110 -eq ${roi_dir}/left_calcarine.nii.gz
    mrcalc ${gif_parc} 116 -eq ${roi_dir}/left_cuneus.nii.gz
    mrcalc ${gif_parc} 198 -eq ${roi_dir}/left_SOG.nii.gz
    mrcalc ${gif_parc} 146 -eq ${roi_dir}/left_MOG.nii.gz
    mrcalc ${gif_parc} 200 -eq ${roi_dir}/left_supPar.nii.gz
    ${ROIsplit} --parc ${gif_parc} --label 124 --sections 2 --out ${roi_dir}/left_FG_split.nii.gz
    mrcalc ${roi_dir}/left_FG_split.nii.gz 1 -eq ${roi_dir}/left_FG_pos.nii.gz
    mrcalc ${gif_parc} 162 -eq ${roi_dir}/left_FGocc.nii.gz
    mrcalc ${roi_dir}/left_calcarine.nii.gz \
      ${roi_dir}/left_cuneus.nii.gz -add \
      ${roi_dir}/left_FGocc.nii.gz -add \
      ${roi_dir}/left_SOG.nii.gz -add \
      ${roi_dir}/left_MOG.nii.gz -add \
      ${roi_dir}/left_supPar.nii.gz -add \
      ${roi_dir}/left_FG_pos.nii.gz -add \
      ${roi_dir}/left_dorsoMed_termination.nii.gz -force
fi
# Left VentroMedial Sub-fasciculus TERMINATION
if [ ! -f ${roi_dir}/left_ventroMed_termination.nii.gz ] ; then
    mrcalc ${gif_parc} 110 -eq ${roi_dir}/left_calcarine.nii.gz
    mrcalc ${gif_parc} 116 -eq ${roi_dir}/left_cuneus.nii.gz
    mrcalc ${gif_parc} 136 -eq ${roi_dir}/left_lingual.nii.gz
    mrcalc ${gif_parc} 198 -eq ${roi_dir}/left_SOG.nii.gz
    mrcalc ${gif_parc} 146 -eq ${roi_dir}/left_MOG.nii.gz
    mrcalc ${gif_parc} 130 -eq ${roi_dir}/left_IOG.nii.gz
    mrcalc ${gif_parc} 200 -eq ${roi_dir}/left_supPar.nii.gz
    mrcalc ${gif_parc} 170 -eq ${roi_dir}/left_preCun.nii.gz
    ${ROIsplit} --parc ${gif_parc} --label 124 --sections 2 --out ${roi_dir}/left_FG_split.nii.gz
    mrcalc ${roi_dir}/left_FG_split.nii.gz 1 -eq ${roi_dir}/left_FG_pos.nii.gz
    mrcalc ${gif_parc} 162 -eq ${roi_dir}/left_FGocc.nii.gz
    mrcalc ${roi_dir}/left_calcarine.nii.gz \
      ${roi_dir}/left_cuneus.nii.gz -add \
      ${roi_dir}/left_lingual.nii.gz -add \
      ${roi_dir}/left_FGocc.nii.gz -add \
      ${roi_dir}/left_SOG.nii.gz -add \
      ${roi_dir}/left_MOG.nii.gz -add \
      ${roi_dir}/left_IOG.nii.gz -add \
      ${roi_dir}/left_supPar.nii.gz -add \
      ${roi_dir}/left_preCun.nii.gz -add \
      ${roi_dir}/left_FG_pos.nii.gz -add \
      ${roi_dir}/left_ventroMed_termination.nii.gz -force
fi
#
#   Right Hemisphere
# Right VentroLateral Sub-fasciculus SEED
if [ ! -f ${roi_dir}/right_ventroLat_seed.nii.gz ] ; then
    mrcalc ${gif_parc} 163 -eq ${roi_dir}/right_IFOF_parsOp.nii.gz
    mrcalc ${gif_parc} 165 -eq ${roi_dir}/right_IFOF_parsOrb.nii.gz
    mrcalc ${gif_parc} 205 -eq ${roi_dir}/right_IFOF_parsTri.nii.gz
    mrcalc ${roi_dir}/right_IFOF_parsOp.nii.gz \
      ${roi_dir}/right_IFOF_parsOrb.nii.gz -add \
      ${roi_dir}/right_IFOF_parsTri.nii.gz -add \
      ${roi_dir}/right_ventroLat_seed.nii.gz -force
fi
# Right DorsoMedial Sub-fasciculus SEED
if [ ! -f ${roi_dir}/right_dorsoMed_seed.nii.gz ] ; then
    mrcalc ${gif_parc} 143 -eq ${roi_dir}/right_dorsoMed_seed.nii.gz
fi
#Right VentroMedial Sub-fasciculus SEED
if [ ! -f ${roi_dir}/right_ventroMed_seed.nii.gz ] ; then
    mrcalc ${gif_parc} 147 -eq ${roi_dir}/right_orbital_med.nii.gz
    mrcalc ${gif_parc} 179 -eq ${roi_dir}/right_orbital_pos.nii.gz
    mrcalc ${gif_parc} 105 -eq ${roi_dir}/right_orbital_ant.nii.gz
    mrcalc ${gif_parc} 137 -eq ${roi_dir}/right_orbital_lat.nii.gz
    mrcalc ${roi_dir}/right_orbital_med.nii.gz \
      ${roi_dir}/right_orbital_pos.nii.gz -add \
      ${roi_dir}/right_orbital_ant.nii.gz -add \
      ${roi_dir}/right_orbital_lat.nii.gz -add \
      ${roi_dir}/right_ventroMed_seed.nii.gz -force
fi
# Right VentroLateral Sub-fasciculus TERMINATION
if [ ! -f ${roi_dir}/right_ventroLat_termination.nii.gz ] ; then
    mrcalc ${gif_parc} 109 -eq ${roi_dir}/right_calcarine.nii.gz
    mrcalc ${gif_parc} 197 -eq ${roi_dir}/right_SOG.nii.gz
    mrcalc ${gif_parc} 145 -eq ${roi_dir}/right_MOG.nii.gz
    mrcalc ${gif_parc} 129 -eq ${roi_dir}/right_IOG.nii.gz
    mrcalc ${gif_parc} 135 -eq ${roi_dir}/right_lingual.nii.gz
    mrcalc ${gif_parc} 199 -eq ${roi_dir}/right_supPar.nii.gz
    mrcalc ${gif_parc} 169 -eq ${roi_dir}/right_preCun.nii.gz
    ${ROIsplit} --parc ${gif_parc} --label 123 --sections 2 --out ${roi_dir}/right_FG_split.nii.gz
    mrcalc ${roi_dir}/right_FG_split.nii.gz 1 -eq ${roi_dir}/right_FG_pos.nii.gz
    mrcalc ${gif_parc} 161 -eq ${roi_dir}/right_FGocc.nii.gz
    mrcalc ${roi_dir}/right_calcarine.nii.gz \
      ${roi_dir}/right_SOG.nii.gz -add \
      ${roi_dir}/right_FGocc.nii.gz -add \
      ${roi_dir}/right_MOG.nii.gz -add \
      ${roi_dir}/right_IOG.nii.gz -add \
      ${roi_dir}/right_lingual.nii.gz -add \
      ${roi_dir}/right_supPar.nii.gz -add \
      ${roi_dir}/right_preCun.nii.gz -add \
      ${roi_dir}/right_FG_pos.nii.gz -add \
      ${roi_dir}/right_ventroLat_termination.nii.gz -force
fi
# Right DorsoMedial Sub-fasciculus TERMINATION
if [ ! -f ${roi_dir}/right_dorsoMed_termination.nii.gz ] ; then
    mrcalc ${gif_parc} 109 -eq ${roi_dir}/right_calcarine.nii.gz
    mrcalc ${gif_parc} 115 -eq ${roi_dir}/right_cuneus.nii.gz
    mrcalc ${gif_parc} 197 -eq ${roi_dir}/right_SOG.nii.gz
    mrcalc ${gif_parc} 145 -eq ${roi_dir}/right_MOG.nii.gz
    mrcalc ${gif_parc} 199 -eq ${roi_dir}/right_supPar.nii.gz
    ${ROIsplit} --parc ${gif_parc} --label 123 --sections 2 --out ${roi_dir}/right_FG_split.nii.gz
    mrcalc ${roi_dir}/right_FG_split.nii.gz 1 -eq ${roi_dir}/right_FG_pos.nii.gz
    mrcalc ${gif_parc} 161 -eq ${roi_dir}/right_FGocc.nii.gz
    mrcalc ${roi_dir}/right_calcarine.nii.gz \
      ${roi_dir}/right_cuneus.nii.gz -add \
      ${roi_dir}/right_FGocc.nii.gz -add \
      ${roi_dir}/right_SOG.nii.gz -add \
      ${roi_dir}/right_MOG.nii.gz -add \
      ${roi_dir}/right_supPar.nii.gz -add \
      ${roi_dir}/right_FG_pos.nii.gz -add \
      ${roi_dir}/right_dorsoMed_termination.nii.gz -force
fi
# Right VentroMedial Sub-fasciculus TERMINATION
if [ ! -f ${roi_dir}/right_ventroMed_termination.nii.gz ] ; then
    mrcalc ${gif_parc} 109 -eq ${roi_dir}/right_calcarine.nii.gz
    mrcalc ${gif_parc} 115 -eq ${roi_dir}/right_cuneus.nii.gz
    mrcalc ${gif_parc} 135 -eq ${roi_dir}/right_lingual.nii.gz
    mrcalc ${gif_parc} 197 -eq ${roi_dir}/right_SOG.nii.gz
    mrcalc ${gif_parc} 145 -eq ${roi_dir}/right_MOG.nii.gz
    mrcalc ${gif_parc} 129 -eq ${roi_dir}/right_IOG.nii.gz
    mrcalc ${gif_parc} 199 -eq ${roi_dir}/right_supPar.nii.gz
    mrcalc ${gif_parc} 169 -eq ${roi_dir}/right_preCun.nii.gz
    ${ROIsplit} --parc ${gif_parc} --label 123 --sections 2 --out ${roi_dir}/right_FG_split.nii.gz
    mrcalc ${roi_dir}/right_FG_split.nii.gz 1 -eq ${roi_dir}/right_FG_pos.nii.gz
    mrcalc ${gif_parc} 161 -eq ${roi_dir}/right_FGocc.nii.gz
    mrcalc ${roi_dir}/right_calcarine.nii.gz \
      ${roi_dir}/right_cuneus.nii.gz -add \
      ${roi_dir}/right_lingual.nii.gz -add \
      ${roi_dir}/right_FGocc.nii.gz -add \
      ${roi_dir}/right_SOG.nii.gz -add \
      ${roi_dir}/right_MOG.nii.gz -add \
      ${roi_dir}/right_IOG.nii.gz -add \
      ${roi_dir}/right_supPar.nii.gz -add \
      ${roi_dir}/right_preCun.nii.gz -add \
      ${roi_dir}/right_FG_pos.nii.gz -add \
      ${roi_dir}/right_ventroMed_termination.nii.gz -force
fi


echo "Dilating the cortical ROIs into the 5tt white matter and 7T mask"
#Dilation
if [ ! -f ${roi_dir}/left_ventroLat_seed_dil.nii.gz ]; then
    ${dilation} --hsvs_5tt ${fivett} --mask ${mask_dir}/left_IFOFvl_mask_dil.nii.gz --in ${roi_dir}/left_ventroLat_seed.nii.gz --out ${roi_dir}/left_ventroLat_seed_dil.nii.gz
    ${dilation} --hsvs_5tt ${fivett} --mask ${mask_dir}/left_IFOFdm_mask_dil.nii.gz --in ${roi_dir}/left_dorsoMed_seed.nii.gz --out ${roi_dir}/left_dorsoMed_seed_dil.nii.gz
    ${dilation} --hsvs_5tt ${fivett} --mask ${mask_dir}/left_IFOFvm_mask_dil.nii.gz --in ${roi_dir}/left_ventroMed_seed.nii.gz --out ${roi_dir}/left_ventroMed_seed_dil.nii.gz
    ${dilation} --hsvs_5tt ${fivett} --mask ${mask_dir}/left_IFOFvl_mask_dil.nii.gz --in ${roi_dir}/left_ventroLat_termination.nii.gz --out ${roi_dir}/left_ventroLat_termination_dil.nii.gz
    ${dilation} --hsvs_5tt ${fivett} --mask ${mask_dir}/left_IFOFdm_mask_dil.nii.gz --in ${roi_dir}/left_dorsoMed_termination.nii.gz --out ${roi_dir}/left_dorsoMed_termination_dil.nii.gz
    ${dilation} --hsvs_5tt ${fivett} --mask ${mask_dir}/left_IFOFvm_mask_dil.nii.gz --in ${roi_dir}/left_ventroMed_termination.nii.gz --out ${roi_dir}/left_ventroMed_termination_dil.nii.gz
fi
if [ ! -f ${roi_dir}/right_ventroLat_seed_dil.nii.gz ]; then
    ${dilation} --hsvs_5tt ${fivett} --mask ${mask_dir}/right_IFOFvl_mask_dil.nii.gz --in ${roi_dir}/right_ventroLat_seed.nii.gz --out ${roi_dir}/right_ventroLat_seed_dil.nii.gz
    ${dilation} --hsvs_5tt ${fivett} --mask ${mask_dir}/right_IFOFdm_mask_dil.nii.gz --in ${roi_dir}/right_dorsoMed_seed.nii.gz --out ${roi_dir}/right_dorsoMed_seed_dil.nii.gz
    ${dilation} --hsvs_5tt ${fivett} --mask ${mask_dir}/right_IFOFvm_mask_dil.nii.gz --in ${roi_dir}/right_ventroMed_seed.nii.gz --out ${roi_dir}/right_ventroMed_seed_dil.nii.gz
    ${dilation} --hsvs_5tt ${fivett} --mask ${mask_dir}/right_IFOFvl_mask_dil.nii.gz --in ${roi_dir}/right_ventroLat_termination.nii.gz --out ${roi_dir}/right_ventroLat_termination_dil.nii.gz
    ${dilation} --hsvs_5tt ${fivett} --mask ${mask_dir}/right_IFOFdm_mask_dil.nii.gz --in ${roi_dir}/right_dorsoMed_termination.nii.gz --out ${roi_dir}/right_dorsoMed_termination_dil.nii.gz
    ${dilation} --hsvs_5tt ${fivett} --mask ${mask_dir}/right_IFOFvm_mask_dil.nii.gz --in ${roi_dir}/right_ventroMed_termination.nii.gz --out ${roi_dir}/right_ventroMed_termination_dil.nii.gz
fi


echo "Performing tractography"

#Tckgen Probabilistic (LEFT: IFOFvl)
if [ ! -f ${out_dir}/left_IFOFvl.tck ]; then
    tckgen ${FOD} -algorithm ${algorithm} -act ${fivett} -seed_image ${roi_dir}/left_ventroLat_seed_dil.nii.gz -include ${roi_dir}/left_ventroLat_termination_dil.nii.gz -maxlength 300 ${out_dir}/left_IFOFvl_prob_SW.tck -seed_unidirectional -force -mask ${mask_dir}/left_IFOFvl_mask_dil.nii.gz ${options} -seeds 100000000 -select 10k
    tckgen ${FOD} -algorithm ${algorithm} -act ${fivett} -seed_image ${roi_dir}/left_ventroLat_termination_dil.nii.gz -include ${roi_dir}/left_ventroLat_seed_dil.nii.gz -maxlength 300 ${out_dir}/left_IFOFvl_prob_WS.tck -seed_unidirectional -force -mask ${mask_dir}/left_IFOFvl_mask_dil.nii.gz ${options} -seeds 100000000 -select 10k
    tckedit ${out_dir}/left_IFOFvl_prob_SW.tck ${out_dir}/left_IFOFvl_prob_WS.tck ${out_dir}/left_IFOFvl_prob_unpruned.tck -force
    tckedit ${out_dir}/left_IFOFvl_prob_unpruned.tck -include ${roi_dir}/left_ventroLat_seed_dil.nii.gz -include ${roi_dir}/left_ventroLat_termination_dil.nii.gz ${out_dir}/left_IFOFvl_prob_unpruned_ends.tck -ends_only -force
    ${pruning} -in ${out_dir}/left_IFOFvl_prob_unpruned_ends.tck -templ_im ${T1} -out ${out_dir}/left_IFOFvl.tck -thr 0.01
    if [ -f ${out_dir}/left_IFOFvl.tck ]; then
        rm -r ${out_dir}/left_IFOFvl_prob_SW.tck ${out_dir}/left_IFOFvl_prob_WS.tck ${out_dir}/left_IFOFvl_prob_unpruned.tck ${out_dir}/left_IFOFvl_prob_unpruned_ends.tck
    fi
fi
#Tckgen Probabilistic (RIGHT: IFOFvl)
if [ ! -f ${out_dir}/right_IFOFvl.tck ]; then
    tckgen ${FOD} -algorithm ${algorithm} -act ${fivett} -seed_image ${roi_dir}/right_ventroLat_seed_dil.nii.gz -include ${roi_dir}/right_ventroLat_termination_dil.nii.gz -maxlength 300 ${out_dir}/right_IFOFvl_prob_SW.tck -seed_unidirectional -force -mask ${mask_dir}/right_IFOFvl_mask_dil.nii.gz ${options} -seeds 100000000 -select 10k
    tckgen ${FOD} -algorithm ${algorithm} -act ${fivett} -seed_image ${roi_dir}/right_ventroLat_termination_dil.nii.gz -include ${roi_dir}/right_ventroLat_seed_dil.nii.gz -maxlength 300 ${out_dir}/right_IFOFvl_prob_WS.tck -seed_unidirectional -force -mask ${mask_dir}/right_IFOFvl_mask_dil.nii.gz ${options} -seeds 100000000 -select 10k
    tckedit ${out_dir}/right_IFOFvl_prob_SW.tck ${out_dir}/right_IFOFvl_prob_WS.tck ${out_dir}/right_IFOFvl_prob_unpruned.tck -force
    tckedit ${out_dir}/right_IFOFvl_prob_unpruned.tck -include ${roi_dir}/right_ventroLat_seed_dil.nii.gz -include ${roi_dir}/right_ventroLat_termination_dil.nii.gz ${out_dir}/right_IFOFvl_prob_unpruned_ends.tck -ends_only -force
    ${pruning} -in ${out_dir}/right_IFOFvl_prob_unpruned_ends.tck -templ_im ${T1} -out ${out_dir}/right_IFOFvl.tck -thr 0.01
    if [ -f ${out_dir}/right_IFOFvl.tck ]; then
        rm -r ${out_dir}/right_IFOFvl_prob_SW.tck ${out_dir}/right_IFOFvl_prob_WS.tck ${out_dir}/right_IFOFvl_prob_unpruned.tck ${out_dir}/right_IFOFvl_prob_unpruned_ends.tck
    fi
fi
#Tckgen Probabilistic (LEFT: IFOFvm)
if [ ! -f ${out_dir}/left_IFOFvm.tck ]; then
    tckgen ${FOD} -algorithm ${algorithm} -act ${fivett} -seed_image ${roi_dir}/left_ventroMed_seed_dil.nii.gz -include ${roi_dir}/left_ventroMed_termination_dil.nii.gz -maxlength 300 ${out_dir}/left_IFOFvm_prob_SW.tck -seed_unidirectional -force -mask ${mask_dir}/left_IFOFvm_mask_dil.nii.gz ${options} -seeds 100000000 -select 10k
    tckgen ${FOD} -algorithm ${algorithm} -act ${fivett} -seed_image ${roi_dir}/left_ventroMed_termination_dil.nii.gz -include ${roi_dir}/left_ventroMed_seed_dil.nii.gz -maxlength 300 ${out_dir}/left_IFOFvm_prob_WS.tck -seed_unidirectional -force -mask ${mask_dir}/left_IFOFvm_mask_dil.nii.gz ${options} -seeds 100000000 -select 10k
    tckedit ${out_dir}/left_IFOFvm_prob_SW.tck ${out_dir}/left_IFOFvm_prob_WS.tck ${out_dir}/left_IFOFvm_prob_unpruned.tck -force
    tckedit ${out_dir}/left_IFOFvm_prob_unpruned.tck -include ${roi_dir}/left_ventroMed_seed_dil.nii.gz -include ${roi_dir}/left_ventroMed_termination_dil.nii.gz ${out_dir}/left_IFOFvm_prob_unpruned_ends.tck -ends_only -force
    ${pruning} -in ${out_dir}/left_IFOFvm_prob_unpruned_ends.tck -templ_im ${T1} -out ${out_dir}/left_IFOFvm.tck -thr 0.01
    if [ -f ${out_dir}/left_IFOFvm.tck ]; then
        rm -r ${out_dir}/left_IFOFvm_prob_SW.tck ${out_dir}/left_IFOFvm_prob_WS.tck ${out_dir}/left_IFOFvm_prob_unpruned.tck ${out_dir}/left_IFOFvm_prob_unpruned_ends.tck
    fi
fi
if [ ! -f ${out_dir}/right_IFOFvm.tck ]; then
    tckgen ${FOD} -algorithm ${algorithm} -act ${fivett} -seed_image ${roi_dir}/right_ventroMed_seed_dil.nii.gz -include ${roi_dir}/right_ventroMed_termination_dil.nii.gz -maxlength 300 ${out_dir}/right_IFOFvm_prob_SW.tck -seed_unidirectional -force -mask ${mask_dir}/right_IFOFvm_mask_dil.nii.gz ${options} -seeds 100000000 -select 10k
    tckgen ${FOD} -algorithm ${algorithm} -act ${fivett} -seed_image ${roi_dir}/right_ventroMed_termination_dil.nii.gz -include ${roi_dir}/right_ventroMed_seed_dil.nii.gz -maxlength 300 ${out_dir}/right_IFOFvm_prob_WS.tck -seed_unidirectional -force -mask ${mask_dir}/right_IFOFvm_mask_dil.nii.gz ${options} -seeds 100000000 -select 10k
    tckedit ${out_dir}/right_IFOFvm_prob_SW.tck ${out_dir}/right_IFOFvm_prob_WS.tck ${out_dir}/right_IFOFvm_prob_unpruned.tck -force
    tckedit ${out_dir}/right_IFOFvm_prob_unpruned.tck -include ${roi_dir}/right_ventroMed_seed_dil.nii.gz -include ${roi_dir}/right_ventroMed_termination_dil.nii.gz ${out_dir}/right_IFOFvm_prob_unpruned_ends.tck -ends_only -force
    ${pruning} -in ${out_dir}/right_IFOFvm_prob_unpruned_ends.tck -templ_im ${T1} -out ${out_dir}/right_IFOFvm.tck -thr 0.01
    if [ -f ${out_dir}/right_IFOFvm.tck ]; then
        rm -r ${out_dir}/right_IFOFvm_prob_SW.tck ${out_dir}/right_IFOFvm_prob_WS.tck ${out_dir}/right_IFOFvm_prob_unpruned.tck ${out_dir}/right_IFOFvm_prob_unpruned_ends.tck
    fi
fi
#Tckgen Probabilistic (LEFT: IFOFdm)
if [ ! -f ${out_dir}/left_IFOFdm.tck ]; then
    tckgen ${FOD} -algorithm ${algorithm} -act ${fivett} -seed_image ${roi_dir}/left_dorsoMed_seed_dil.nii.gz -include ${roi_dir}/left_dorsoMed_termination_dil.nii.gz -maxlength 300 ${out_dir}/left_IFOFdm_prob_SW.tck -seed_unidirectional -force -mask ${mask_dir}/left_IFOFdm_mask_dil.nii.gz ${options} -seeds 100000000 -select 10k
    tckgen ${FOD} -algorithm ${algorithm} -act ${fivett} -seed_image ${roi_dir}/left_dorsoMed_termination_dil.nii.gz -include ${roi_dir}/left_dorsoMed_seed_dil.nii.gz -maxlength 300 ${out_dir}/left_IFOFdm_prob_WS.tck -seed_unidirectional -force -mask ${mask_dir}/left_IFOFdm_mask_dil.nii.gz ${options} -seeds 100000000 -select 10k
    tckedit ${out_dir}/left_IFOFdm_prob_SW.tck ${out_dir}/left_IFOFdm_prob_WS.tck ${out_dir}/left_IFOFdm_prob_unpruned.tck -force
    tckedit ${out_dir}/left_IFOFdm_prob_unpruned.tck -include ${roi_dir}/left_dorsoMed_seed_dil.nii.gz -include ${roi_dir}/left_dorsoMed_termination_dil.nii.gz ${out_dir}/left_IFOFdm_prob_unpruned_ends.tck -ends_only -force
    ${pruning} -in ${out_dir}/left_IFOFdm_prob_unpruned_ends.tck -templ_im ${T1} -out ${out_dir}/left_IFOFdm.tck -thr 0.01
    if [ -f ${out_dir}/left_IFOFdm.tck ]; then
        rm -r ${out_dir}/left_IFOFdm_prob_SW.tck ${out_dir}/left_IFOFdm_prob_WS.tck ${out_dir}/left_IFOFdm_prob_unpruned.tck ${out_dir}/left_IFOFdm_prob_unpruned_ends.tck
    fi
fi
if [ ! -f ${out_dir}/right_IFOFdm.tck ]; then
    tckgen ${FOD} -algorithm ${algorithm} -act ${fivett} -seed_image ${roi_dir}/right_dorsoMed_seed_dil.nii.gz -include ${roi_dir}/right_dorsoMed_termination_dil.nii.gz -maxlength 300 ${out_dir}/right_IFOFdm_prob_SW.tck -seed_unidirectional -force -mask ${mask_dir}/right_IFOFdm_mask_dil.nii.gz ${options} -seeds 100000000 -select 10k
    tckgen ${FOD} -algorithm ${algorithm} -act ${fivett} -seed_image ${roi_dir}/right_dorsoMed_termination_dil.nii.gz -include ${roi_dir}/right_dorsoMed_seed_dil.nii.gz -maxlength 300 ${out_dir}/right_IFOFdm_prob_WS.tck -seed_unidirectional -force -mask ${mask_dir}/right_IFOFdm_mask_dil.nii.gz ${options} -seeds 100000000 -select 10k
    tckedit ${out_dir}/right_IFOFdm_prob_SW.tck ${out_dir}/right_IFOFdm_prob_WS.tck ${out_dir}/right_IFOFdm_prob_unpruned.tck -force
    tckedit ${out_dir}/right_IFOFdm_prob_unpruned.tck -include ${roi_dir}/right_dorsoMed_seed_dil.nii.gz -include ${roi_dir}/right_dorsoMed_termination_dil.nii.gz ${out_dir}/right_IFOFdm_prob_unpruned_ends.tck -ends_only -force
    ${pruning} -in ${out_dir}/right_IFOFdm_prob_unpruned_ends.tck -templ_im ${T1} -out ${out_dir}/right_IFOFdm.tck -thr 0.01
    if [ -f ${out_dir}/right_IFOFdm.tck ]; then
        rm -r ${out_dir}/right_IFOFdm_prob_SW.tck ${out_dir}/right_IFOFdm_prob_WS.tck ${out_dir}/right_IFOFdm_prob_unpruned.tck ${out_dir}/right_IFOFdm_prob_unpruned_ends.tck
    fi
fi