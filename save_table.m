function save_table(tbl, fileName)
%SAVE_TABLE Write a table, falling back to a timestamped name if the file is open.

try
    writetable(tbl, fileName);
catch err
    [folder, name, ext] = fileparts(fileName);
    fallbackName = fullfile(folder, sprintf('%s_%s%s', name, ...
        datestr(now, 'yyyymmdd_HHMMSS'), ext)); %#ok<TNOW1,DATST>
    warning('Could not write %s (%s). Wrote %s instead.', fileName, err.message, fallbackName);
    writetable(tbl, fallbackName);
end
end
