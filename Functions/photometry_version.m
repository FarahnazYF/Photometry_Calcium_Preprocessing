function info = photometry_version()
%PHOTOMETRY_VERSION Version of this pipeline and a fingerprint of its code.
%
%   info = photometry_version()
%
% Saved with every result file, so that you can tell later which code made
% it (see CHANGELOG.md for what changed between versions).
%
%   info.version         e.g. '1.1.0'. Raised whenever a change affects the
%                        results or the saved fields.
%   info.format_version  number of the layout of the saved "results"
%                        variable (which fields exist and what they mean).
%   info.code_checksum   fingerprint (MD5) of all .m files in the Functions
%                        folder; line endings are ignored. Two result files
%                        with the same fingerprint were made by exactly the
%                        same functions. '' if it could not be calculated
%                        (for example when MATLAB runs without Java).
%
% To check which code made a result file, compare results.code_checksum
% with the code_checksum this function returns in your copy of the code.

info.version = '1.1.0';
info.format_version = 2;
info.code_checksum = '';
try
    folder = fileparts(mfilename('fullpath'));
    listing = dir(fullfile(folder, '*.m'));
    names = sort({listing.name});
    digest = java.security.MessageDigest.getInstance('MD5');
    for k = 1:numel(names)
        fid = fopen(fullfile(folder, names{k}), 'r');
        if fid < 0, error('photometry:Version', 'Cannot read %s.', names{k}); end
        bytes = fread(fid, Inf, '*uint8');
        fclose(fid);
        bytes(bytes == 13) = [];               % ignore Windows line endings
        digest.update(uint8(names{k}));
        digest.update(bytes);
    end
    checksum = typecast(digest.digest(), 'uint8');
    info.code_checksum = lower(reshape(dec2hex(checksum, 2)', 1, []));
catch
    % No Java, or a file could not be read: the fingerprint stays empty.
end
end
