function root = s23_root()
% S23_ROOT spandan repo root (common/ -> segment23 -> experiments -> matlab -> spandan).
d = fileparts(mfilename('fullpath'));
root = fileparts(fileparts(fileparts(fileparts(d))));
end
