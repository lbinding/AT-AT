#!/bin/sh

#  prune_tck.sh
#  
#
#  Created by Sjoerd Vos on 16/08/2018 - based on Matteo Mancini's idea
#
#      09/07/2020 ~ Lawrence Binding
#           Updated to work on the current systems.
#      23/02/2021 ~ Sjoerd Vos
#           Swapped to fslmaths and fslstats instead of niftyseg
#

# Get script name
script_name=`basename $0`

# Set right MRtrix3 version
export PATH="/opt/mrtrix3/bin:${PATH}"
# Set FSL settings
export FSLDIR=/usr2/mrtools/fsl-6.0.3/
export FSLOUTPUTTYPE=NIFTI_GZ
export PATH=${FSLDIR}/bin:${PATH}

# Set relative threshold to use
def_thr=0.01

# Check inputs
correct_input=1
if [ $# -eq 0 ] ; then
  correct_input=0

else

  # Remove the first argument (this shell's name)
  i=0
  for var in "$@"
  do
    args[$i]=$var
    let i=$i+1
  done

  # Loop over arguments looking for -i and -o
  args=("$@")
  i=0
  while [ $i -lt $# ]
  do
    if ( [ ${args[i]} = "-i" ] || [ ${args[i]} = "-in" ] ) ; then
      # Set input track-file
      let i=$i+1
      tck_in=${args[i]}
    elif ( [ ${args[i]} = "-o" ] || [ ${args[i]} = "-out" ] ) ; then
      # Set output track-file
      let i=$i+1
      tck_out=${args[i]}
    elif [ ${args[i]} = "-templ_im" ] ; then
      # specify template image
      let i=$i+1
      templ_im=${args[i]}
    elif [ ${args[i]} = "-thr" ] ; then
      # specify threshold [0 - 1]
      let i=$i+1
      thr=${args[i]}
    fi
    let i=$i+1
  done

  # Check if user gave correct inputs
  if ( [ -z ${templ_im} ] || [ -z ${tck_in} ] ) ; then
    correct_input=0
    echo "Please provide input track-file and template image"
  fi

fi

if ( [[ ${correct_input} -eq 0 ]] ) ; then
  echo ""
  echo "Incorrect input. Please see below for correct use"
  echo ""
  echo "Options:"
  echo " -in:        Input tracts (*tck) -- REQUIRED"
  echo " -templ_im:  Input template image (*.nii, *.nii.gz, or *.mif) -- REQUIRED"
  echo " -out:       Output tracts (*tck) -- OPTIONAL"  
  echo ""
  echo "${script_name} -in tracts_unpruned.tck -templ_im T1.nii.gz -out tracts.tck"
  echo ""
  exit
else 
  echo "Correct input, proceeding..."
fi

# Derive output name from input if output filename nor given
if [ -z ${tck_out} ] ; then
  tck_out=`echo ${tck_in} | sed s/.tck/_pruned.tck/`
fi
# use user-provided threshold if between 0 and 1
if [ -z ${thr} ] ; then
  thr=${def_thr}
else
  if ( [ ${thr} -lt 0 ] || [ ${thr} -gt 1 ] ) ; then
    thr=${def_thr}
  fi
fi

# Get input folder
in_dir=`dirname ${tck_in}`

# Check input files exist
if [ ! -f ${tck_in} ] ; then
  echo "Error: input tracts file (${tck_in}) does not exist" ; exit
fi
if [ ! -f ${templ_im} ] ; then
  echo "Error: input template image (${templ_im}) does not exist" ; exit
fi

# Get tract map from tck-file
tckmap ${tck_in} -template ${templ_im} ${in_dir}/tmp_tckmap.nii.gz

# Get max value from tract map
max_val=`fslstats ${in_dir}/tmp_tckmap.nii.gz -R | awk '{print $2}'`
# Set lowest value based on that value and above defined relative threshold
thr_val=`echo "${max_val}*${thr}" | bc`

# Use tract map and threshold value to generate exclusion ROI
fslmaths ${in_dir}/tmp_tckmap.nii.gz -thr ${thr_val} -bin -kernel 3D -dilM -sub 1 -mul -1 ${in_dir}/tmp_excl_ROI.nii.gz

# Modify tracts
tckedit ${tck_in} -exclude ${in_dir}/tmp_excl_ROI.nii.gz ${tck_out}

# Clean up
rm ${in_dir}/tmp_tckmap.nii.gz ${in_dir}/tmp_excl_ROI.nii.gz

