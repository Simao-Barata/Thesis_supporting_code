function style_figures()
%STYLE_FIGURES Size and style every open figure for printing in the thesis.
%   Figures are drawn at the width they will occupy on the page, so a point of
%   font here is a point of font on paper.  Drawing them large and letting
%   \includegraphics shrink them is what makes printed labels small and lines
%   faint: a figure 40 cm wide squeezed into 15 cm takes its 16 pt text down to
%   6 pt and its 1.5 pt lines down to half a point.
%
%   Each figure keeps the shape it was given, only its size changes: the height
%   follows the width through the aspect ratio the plotting code chose.  Call it
%   at the end of a script, after the last figure has been drawn, and export
%   with exportgraphics at 300 dpi, which then writes the true printed size.
printWidth_cm = 15.0;   % text block of the thesis page
fontSize_pt = 9;        % axis labels, tick labels and titles
legendSize_pt = 8;
lineWidth_pt = 1.0;
markerSize_pt = 3.5;

for f = findall(groot, 'Type', 'figure')'
    % Size first: fonts are points of the figure, so they only mean what they
    % say once the figure is the size it will be printed at.
    old = get(f, 'Position');
    aspect = old(4) / old(3);
    set(f, 'Units', 'centimeters', ...
        'Position', [2, 2, printWidth_cm, printWidth_cm * aspect]);

    set(findall(f, 'Type', 'axes'), 'FontSize', fontSize_pt, 'FontWeight', 'bold', ...
        'LabelFontSizeMultiplier', 1, 'TitleFontSizeMultiplier', 1, ...
        'TitleFontWeight', 'bold', 'LineWidth', 0.5);
    set(findall(f, 'Type', 'legend'), 'FontSize', legendSize_pt, 'FontWeight', 'bold');
    for c = findall(f, 'Type', 'colorbar')'
        set([c, c.Label], 'FontSize', fontSize_pt, 'FontWeight', 'bold');
    end
    set(findall(f, 'Type', 'text'), 'FontSize', legendSize_pt, 'FontWeight', 'bold');
    % Labels on reference lines drawn with xline and yline.
    set(findall(f, 'Type', 'constantline'), 'FontSize', legendSize_pt, ...
        'FontWeight', 'bold');
    for t = findall(f, 'Type', 'tiledlayout')'
        set([t.Title, t.XLabel, t.YLabel], 'FontSize', fontSize_pt, ...
            'FontWeight', 'bold');
    end

    % Data lines and markers.  A line thinner than about 0.8 pt breaks up in
    % print, and markers sized for a screen swamp a 15 cm figure.
    for h = findall(f, 'Type', 'line')'
        set(h, 'LineWidth', max(h.LineWidth * 0.7, lineWidth_pt));
        if ~strcmp(h.Marker, 'none')
            set(h, 'MarkerSize', min(h.MarkerSize, markerSize_pt));
        end
    end
    set(findall(f, 'Type', 'constantline'), 'LineWidth', 0.8);
    for h = findall(f, 'Type', 'scatter')'
        set(h, 'SizeData', min(h.SizeData, 40));
    end
end
end
