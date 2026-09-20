function root = s23_setup()
% S23_SETUP add production matlab/src (READ-ONLY use) and this segment's common/ to the path.
root = s23_root();
addpath(genpath(fullfile(root, 'matlab', 'src')));
addpath(fileparts(mfilename('fullpath')));
end
