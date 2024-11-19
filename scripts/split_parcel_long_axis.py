#!/usr/bin/env python3
__author__ = 'SBV'
import argparse
import nibabel as nib
import numpy as np
import os
import scipy.ndimage as ndimage


def get_lcc(im):
    # Check dimensions
    if np.ndim(im) == 2:
        return get_2d_lcc(im)
    elif np.ndim(im) == 3:
        return get_3d_lcc(im)


def get_2d_lcc(im):
    """
    Function to obtain largest connected component

    Required inputs
    im:      2D volume to process
    """

    # Get labels and number of labels
    se4 = np.zeros((3, 3))
    se4[1, :] = 1
    se4[:, 1] = 1
    labels, n_labels = ndimage.measurements.label(im, se4)
    # Get histogram of incidence - excluding any indices that are False
    hist_cnt = np.array(np.zeros((n_labels+1,)))
    for i in range(0, n_labels+1):
        if np.any(im[labels == i]):
            hist_cnt[i] = np.sum(labels == i)
    # Return largest component
    largest_cc = labels == np.argmax(hist_cnt)
    return largest_cc


def get_3d_lcc(im):
    """
    Function to obtain largest connected component

    Required inputs
    im:      3D volume to process
    """

    # Get labels and number of labels
    se6 = np.zeros((3, 3, 3))
    se6[1, 1, :] = 1
    se6[1, :, 1] = 1
    se6[:, 1, 1] = 1
    labels, n_labels = ndimage.measurements.label(im, se6)
    # Get histogram of incidence - excluding any indices that are False
    hist_cnt = np.array(np.zeros((n_labels+1,)))
    for i in range(1, n_labels+1):
        if np.any(im[labels == i]):
            hist_cnt[i] = np.sum(labels == i)
    # Return largest component
    largest_cc = labels == np.argmax(hist_cnt)
    return largest_cc


def long_axis(nii_image, label, use_qform=False):
    """
    Function to convert data to 1D function.

    :param nii_image: data to convert
    :param label: label for ROI to extract
    :param use_qform: optional boolean to indicate to use qform instead of voxel coordinates

    :return: main axis of the label
    """

    indices = np.where(get_lcc(nii_image.get_data() == label))
    ind_list = list(zip(indices[0], indices[1], indices[2]))

    if use_qform:
        # world coordinates
        qform = nii_image.get_qform()
        points = np.array(
            [nib.affines.apply_affine(qform, [i, j, k])
            for i, j, k in ind_list]).transpose()
    else:
        # Voxel coordinates
        vox_size = nii_image.header.get_zooms()
        list_size = np.shape(ind_list)
        points = np.transpose(ind_list * np.kron(np.ones((list_size[0], 1)), vox_size))

    mean_points = np.mean(points, axis=1)[:, np.newaxis]

    differences = points - mean_points
    m = np.zeros([3, 3])
    m[0][0] = np.mean(differences[0, :] * differences[0, :])
    m[0][1] = m[1][0] = np.mean(differences[0, :] * differences[1, :])
    m[0][2] = m[2][0] = np.mean(differences[0, :] * differences[2, :])
    m[1][1] = np.mean(differences[1, :] * differences[1, :])
    m[1][2] = m[2][1] = np.mean(differences[1, :] * differences[2, :])
    m[2][2] = np.mean(differences[2, :] * differences[2, :])

    u, _, _ = np.linalg.svd(m)
    main_axis = u[:, 0][:, np.newaxis]

    return main_axis


def get_rotation_matrix(main_axis):

    # Get rotation axis
    ind_m = np.abs(main_axis).argmax(0)
    dest_or = np.zeros((3, 1))
    dest_or[ind_m] = 1
    r_dir = np.cross(main_axis.T, dest_or.T)
    rot_dir = r_dir[0] / np.sqrt(np.sum(np.power(r_dir[0], 2)))
    # Get rotation angle
    rot_angle = np.arccos(np.dot(main_axis.T, dest_or))
    rcos = np.cos(rot_angle)
    rsin = np.sin(rot_angle)

    # Make rotation matrix
    r_mat = np.eye(3)
    r_mat[0, 0] = rcos + rot_dir[0] * rot_dir[0] * (1.0 - rcos)
    r_mat[1, 0] = rot_dir[2] * rsin + rot_dir[1] * rot_dir[0] * (1.0 - rcos)
    r_mat[2, 0] = -rot_dir[1] * rsin + rot_dir[2] * rot_dir[0] * (1.0 - rcos)
    r_mat[0, 1] = -rot_dir[2] * rsin + rot_dir[0] * rot_dir[1] * (1.0 - rcos)
    r_mat[1, 1] = rcos + rot_dir[1] * rot_dir[1] * (1.0 - rcos)
    r_mat[2, 1] = rot_dir[0] * rsin + rot_dir[2] * rot_dir[1] * (1.0 - rcos)
    r_mat[0, 2] = rot_dir[1] * rsin + rot_dir[0] * rot_dir[2] * (1.0 - rcos)
    r_mat[1, 2] = -rot_dir[0] * rsin + rot_dir[1] * rot_dir[2] * (1.0 - rcos)
    r_mat[2, 2] = rcos + rot_dir[2] * rot_dir[2] * (1.0 - rcos)

    return r_mat


parser = argparse.ArgumentParser()
parser.add_argument('--parc', dest='parc', help='GIF parcellation', required=True)
parser.add_argument('--label', dest='label', help='label to extract', type=int, required=True)
parser.add_argument('--sections', dest='sections', help='Number of sections to split the parcel into', type=int, required=True)
parser.add_argument('--out', dest='out_name', help='Output filename', required=False)
args = parser.parse_args()

#f_parc = '/Users/sjoerdvos/Data/example_tractography/C025/diffusion/tracts/mtcsd/gif_parc.nii.gz'
#label = 134

# Get full filename
f_parc = os.path.abspath(args.parc)
in_dir = os.path.dirname(f_parc)
tmp_dir = in_dir

# Load GIF parcellation nifti
parc_nii = nib.load(f_parc)
parc_im = parc_nii.get_data()
qform = parc_nii.header.get_qform()
# Get binary mask of parcel of interest
parcel_im = np.int8(parc_im == args.label)

# Get image axis orientation
nii_axes = nib.aff2axcodes(parc_nii.affine)

tpop_dir = np.zeros((2, 3))
side = 0

# Get main axis of parcel
roi_axis = long_axis(parc_nii, 134)
ind_max = np.abs(roi_axis).argmax(0)
if roi_axis[ind_max] < 0:
    roi_axis = -1 * roi_axis
tpop_dir[side, :] = roi_axis.T

brain_mask = parc_im > 3
com_brain = ndimage.measurements.center_of_mass(brain_mask)

rot_mat = get_rotation_matrix(roi_axis)

rotated_main_axis = np.dot(roi_axis.T, rot_mat)
if rotated_main_axis[0, ind_max] < roi_axis[ind_max]:
    # If the primary component of the rotated axis is smaller than what we started with,
    # # we should probably rotate the other way
    rot_mat = rot_mat.T
    # Apply the rotation matrix to the vector - this should become close to [0 1 0] vector
    rotated_main_axis = np.dot(roi_axis.T, rot_mat)

# Get parcel coordinates
p_ind = parcel_im.ravel().nonzero()
coords_p = np.transpose(np.squeeze(np.array(np.unravel_index(p_ind, parc_im.shape))))
# Get relative coordinates (w.r.t. qform)
rel_coords_p = coords_p + np.kron(np.ones((coords_p.shape[0], 1)), qform[0:3, 3])
# Rotate and translate back
rot_coords_p = np.dot(rel_coords_p, rot_mat) - np.kron(np.ones((coords_p.shape[0], 1)), qform[0:3, 3])

# Test code to see if rotation works
# im_rot = np.zeros(parc_im.shape)
# for c in range(0, rot_coords_p.shape[0]):
#     x_valid = np.int16(np.round(rot_coords_p[c, 0])) >= 0 and np.int16(np.round(rot_coords_p[c, 0])) < parc_im.shape[0]
#     y_valid = np.int16(np.round(rot_coords_p[c, 1])) >= 0 and np.int16(np.round(rot_coords_p[c, 1])) < parc_im.shape[1]
#     z_valid = np.int16(np.round(rot_coords_p[c, 2])) >= 0 and np.int16(np.round(rot_coords_p[c, 2])) < parc_im.shape[2]
#     if x_valid and y_valid and z_valid:
#         im_rot[np.int16(np.round(rot_coords_p[c, 0])), np.int16(
#             np.round(rot_coords_p[c, 1])), np.int16(np.round(rot_coords_p[c, 2]))] = 1
# rot_im_name = os.path.join(tmp_dir, "reoriented_T_WM_%d.nii.gz" % args.label)
# nib.save(nib.Nifti1Image(im_rot, parc_nii.affine, parc_nii.header), rot_im_name)

# Get most outer points (most ant/posterior, most inf/superior, most left/right)
outer_points = np.array((np.min(rot_coords_p[:, ind_max]), np.max(rot_coords_p[:, ind_max])))
section_boundaries = np.linspace(outer_points[0], outer_points[1], args.sections+1)
# ensure boundaries are floored/rounded so all points included
section_boundaries[0] = np.floor(section_boundaries[0])
section_boundaries[-1] = np.ceil(section_boundaries[-1])

# Define which points in the rotated coordinates are within these sections
section_ind = 0 * rel_coords_p[:, 0]
for n in np.arange(0, args.sections):
    lt_part = np.squeeze(rot_coords_p[:, ind_max] < section_boundaries[n + 1])
    gt_part = np.squeeze(rot_coords_p[:, ind_max] >= section_boundaries[n])
    section_ind[np.where(np.logical_and(lt_part, gt_part))] = n+1

# Fill up image
label_out = 0 * parc_im
for c in range(0, coords_p.shape[0]):
    label_out[np.int16(np.round(coords_p[c, 0])), np.int16(
        np.round(coords_p[c, 1])), np.int16(np.round(coords_p[c, 2]))] = section_ind[c]

# Set header info neatly
parc_nii.header['cal_min'] = 0
parc_nii.header['cal_max'] = args.sections
parc_nii.header.set_slope_inter(np.nan, np.nan)

if not args.out_name:
    out_name = os.path.join(os.path.dirname(f_parc), 'parcel_%i_split.nii.gz' % args.label)
else:
    out_name = os.path.abspath(args.out_name)
nib.save(nib.Nifti1Image(label_out.astype('int8'), parc_nii.affine, parc_nii.header), out_name)
