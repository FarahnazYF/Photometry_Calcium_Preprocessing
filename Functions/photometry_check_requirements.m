function photometry_check_requirements()
%PHOTOMETRY_CHECK_REQUIREMENTS Stop early if a required MATLAB toolbox is missing.
%
%   photometry_check_requirements()
%
% The pipeline needs MATLAB R2020a or newer and three toolboxes:
%   Signal Processing Toolbox                butter, filtfilt, findpeaks, freqz
%   Statistics and Machine Learning Toolbox  robustfit, mad, prctile
%   Curve Fitting Toolbox                    fit, fittype (double exponential)
% Checking at the start avoids a crash halfway through a long recording.

needed = { ...
    'butter',         'Signal Processing Toolbox'
    'filtfilt',       'Signal Processing Toolbox'
    'findpeaks',      'Signal Processing Toolbox'
    'freqz',          'Signal Processing Toolbox'
    'robustfit',      'Statistics and Machine Learning Toolbox'
    'mad',            'Statistics and Machine Learning Toolbox'
    'prctile',        'Statistics and Machine Learning Toolbox'
    'fit',            'Curve Fitting Toolbox'
    'fittype',        'Curve Fitting Toolbox'
    'tiledlayout',    'MATLAB R2019b or newer'
    'exportgraphics', 'MATLAB R2020a or newer'};

missing = cellfun(@(name) isempty(which(name)), needed(:,1));
if any(missing)
    list = strcat(needed(missing,1), {' ('}, needed(missing,2), {')'});
    error('photometry:Requirements', ...
        ['These MATLAB functions were not found:\n  %s\n' ...
         'Install the toolboxes named in brackets (Home tab > Add-Ons), then run again.'], ...
        strjoin(list, sprintf('\n  ')));
end
end
