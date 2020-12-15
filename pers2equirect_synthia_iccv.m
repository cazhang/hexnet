clc;
clear all;
close all;
% input image
root_folder = '/home/czhang/Drive2/datasets/synthia/';
folders = dir([root_folder, 'SYNTHIA*']);
full_rgb_names = [];
% paras
view_list = {'/Omni_L', '/Omni_F', '/Omni_R', '/Omni_B'};
target_num_per_seq = 500;
f = 532.740352;
spW = 1048*4;
spH = 1048*2;

for i = 1:length(folders)
    if folders(i).isdir && contains(folders(i).name, 'SUMMER')
    %if folders(i).isdir && contains(folders(i).name, '06')
        fprintf(folders(i).name);
        fprintf('\n');
        % downsample filenames
        [rgb_path, rgb_list, cnt] = get_rgb_path(fullfile(folders(i).folder, folders(i).name));
        fprintf('%d files found\n\n', cnt);
        [short_list, rgb_names] = downsample_files(rgb_list, target_num_per_seq);
        % full filenames
        full_rgb_names = [full_rgb_names; rgb_names];
        % test camera paras
        back_cam_names = strrep(rgb_names, '/RGB', '/CameraParams');
        back_cam_names = strrep(back_cam_names, '.png', '.txt');
        left_cam_names = strrep(back_cam_names, '/Omni_B', '/Omni_L');
        right_cam_names = strrep(back_cam_names, '/Omni_B', '/Omni_R');
        front_cam_names = strrep(back_cam_names, '/Omni_B', '/Omni_F');
        
        
        test_index = 20;
        Lmat = load(left_cam_names(test_index)); 
        Lmat = reshape(Lmat, 4, 4);
        Bmat = load(back_cam_names(test_index)); 
        Bmat = reshape(Bmat, 4, 4);
        Rmat = load(right_cam_names(test_index)); 
        Rmat = reshape(Rmat, 4, 4);
        Fmat = load(front_cam_names(test_index)); 
        Fmat = reshape(Fmat, 4, 4);
        
        T_BL = inv(Bmat) * Lmat;
        T_BR = inv(Bmat) * Rmat;
        T_BF = inv(Bmat) * Fmat;
        T = [T_BL T_BR T_BF];
        disp(T);
    end
end

% all depth names
full_depth_names = strrep(full_rgb_names, '/RGB', '/Depth');
full_gt_names = strrep(full_rgb_names, '/RGB', '/GT/LABELS');
full_color_names = strrep(full_rgb_names, '/RGB', '/GT/COLOR');

% rgb
%rgb_cnt = convert_rgb(full_rgb_names, view_list, spH, spW, f, 3, 0, 1);

% depth
%depth_cnt = convert_rgb(full_depth_names, view_list, spH, spW, f, 1, 0, 2);

% gt-label
gt_cnt = convert_rgb(full_gt_names, view_list, spH, spW, f, 1, 255, 3);

% gt-color
%color_cnt = convert_rgb(full_color_names, view_list, spH, spW, f, 3, 0, 4);

%%%%%%%%%%%%%%%%%%%%%% convert normal images to omnidirectional images
function cnt = convert_rgb(full_rgb_names, view_list, spH, spW, f, nch, invalid_val, index)
% rgb image uint8
cnt = 0;
parfor i = 1:length(full_rgb_names)
    name = full_rgb_names(i);
    finalImg = zeros(spH, spW, nch);
    validMaps = zeros(spH, spW);
    weightMap = zeros(spH, spW, nch);
   
    
    for j = 1:length(view_list)
        Rx = -pi/2 * (j-1);
        Ry = 0;
        rgb_name = strrep(name, '/Omni_B', view_list{j});
        rgb_img = imread(rgb_name);
        rgb_img = double(rgb_img);
        rgb_img = rgb_img(:, :, 1:nch);
       
    
        [sphereImg, validMap] = imNormal2Sphere(rgb_img, [], spW, spH, f, Rx, Ry, index);
        validMaps = validMaps | validMap;
        
        sphereImg = sphereImg .* double(repmat(validMap,[1,1,nch]));
        %sphereCls = sphereCls .* double(repmat(validMap,[1,1,1]));
        
        finalImg = finalImg + sphereImg;
        %finalCls = finalCls + sphereCls;
        weightMap = weightMap + double(validMap);
    end
    weightMap(weightMap==0) = 1;
    finalImg = finalImg ./ weightMap(:,:,1:nch);
    finalImg(~repmat(validMaps,[1,1,nch])) = invalid_val; % make invalid 0
    %finalCls = finalCls ./ weightMap(:,:,1);
    %finalImg(~validMaps) = invalid_val;
    minx = min(finalImg(:));
    maxx = max(finalImg(:));
    fprintf('min: %d\n', minx);
    fprintf('max: %d\n', maxx);
    
    if false
        figure;
        imshow(finalImg./max(finalImg(:)));
    end
    % save image
 
    % 1-RGB: replace /RGB/Stereo_Left/Omni_B
    % 2-depth: repalce /Depth/Stereo_Left/Omni_B
    % 3-gt label: replace /GT/LABELS/Stereo_Left/Omni_B
    % 4-gt color: replace /GT/COLOR/Stereo_Left/Omni_B
    switch index
        case 1 % rgb
            save_to = strrep(name, '/RGB/Stereo_Left/Omni_B', '/pano/RGB');
            finalImg = uint8(finalImg);
        case 2 % depth
            save_to = strrep(name, '/Depth/Stereo_Left/Omni_B', '/pano/Depth');
            finalImg = uint16(finalImg);
        case 3 % gt-label
            save_to = strrep(name, '/GT/LABELS/Stereo_Left/Omni_B', '/pano/GT/LABELS_Correct');
            finalImg = uint8(finalImg);
        case 4 % gt-color
            save_to = strrep(name, '/GT/COLOR/Stereo_Left/Omni_B', '/pano/GT/COLOR');
            finalImg = uint8(finalImg);
        otherwise
            fprintf('unknown index');
    end
   
    save_to = strrep(save_to, '/synthia', '/synthia-iccv');
    [pathpart, namepart, extpart] = fileparts(save_to);
     if ~exist(pathpart, 'dir')
        mkdir(pathpart);
     end
    %unique(finalImg(:))
    imwrite(finalImg, save_to);
    fprintf('save to: %s\n', save_to);
    cnt = cnt+1;
   
end
end



%%%%%%%%%%%%%%%%%%%% util functions

function [new_list, fullnames] = downsample_files(list, ntarget)
nfiles = length(list);
if nfiles <= ntarget
    fprintf('all files returned.\n');
    new_list = list;
else
    step = round(nfiles/ntarget);
    new_idx = 1:step:nfiles;
    new_list = list(new_idx);
end
nfiles = length(new_list);
fullnames = strings(nfiles, 1);
for i =1:nfiles
    fullnames(i) = fullfile(new_list(i).folder, new_list(i).name);
end
end

function [path, filenames, count] = get_rgb_path(seq_dir)
path = fullfile(seq_dir, 'RGB', 'Stereo_Left', 'Omni_B');
filenames = dir([path, '/*.png']);
count = length(filenames);
end
