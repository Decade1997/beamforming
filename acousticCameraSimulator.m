function [] = acousticCameraSimulator()

c = 340;
fs = 44.1e3;
f = 5e3;

array = load('data/arrays/Nor848A-10.mat');
w = array.hiResWeights;
xPos = array.xPos;
yPos = array.yPos;
algorithm = 'DAS';

imageFileColor = imread('data/fig/room.jpg');
imageFileGray = imread('data/fig/roombw.jpg');

% Acoustical coverage / listening points
maxAcousticalCoveringAngleHorizontal = 42;
maxAcousticalCoveringAngleVertical = 30;
distanceToScanningPlane = 3; %in meters
numberOfScanningPointsX = 40;
numberOfScanningPointsY = 30;

maxScanningPlaneExtentX = tan(maxAcousticalCoveringAngleHorizontal*pi/180)*distanceToScanningPlane;
maxScanningPlaneExtentY = tan(maxAcousticalCoveringAngleVertical*pi/180)*distanceToScanningPlane;

scanningAxisX = -maxScanningPlaneExtentX:2*maxScanningPlaneExtentX/(numberOfScanningPointsX-1):maxScanningPlaneExtentX;
scanningAxisY = maxScanningPlaneExtentY:-2*maxScanningPlaneExtentY/(numberOfScanningPointsY-1):-maxScanningPlaneExtentY;

% Get all (x,y) points, organize such that scanning will be left-right-top-bottom
[scanningPointsY, scanningPointsX] = meshgrid(scanningAxisY,scanningAxisX);
scanningPointsX = scanningPointsX(:)';
scanningPointsY = scanningPointsY(:)';


%Sources
xPosSource = [-2.147 -2.147 -2.147 -1.28 -0.3 0 0.37 1.32 2.18 2.18 2.18];
yPosSource = [0.26 -0.15 -0.55 -0.34 1.47 0.5 1.47 -0.33 0.26 -0.15 -0.55];
amplitudes = [-100 -100 -100 0 -100 -100 -100 0 -100 -100 -100];
zPosSource = distanceToScanningPlane*ones(1,length(xPosSource));


%Create input signal
inputSignal = createSignal(xPos, yPos, f, c, fs, xPosSource, yPosSource, zPosSource, amplitudes);

%Calculate steered response
S = calculateSteeredResponse(xPos, yPos, w, inputSignal, f, c, scanningPointsX, scanningPointsY, distanceToScanningPlane, numberOfScanningPointsX, numberOfScanningPointsY);

%Plot image and steered response
plotImage(imageFileColor, S, amplitudes, xPosSource, yPosSource, scanningPointsX, scanningPointsY, maxScanningPlaneExtentX, maxScanningPlaneExtentY)




    % Convert from cartesian points to polar angles
    function [thetaAngles, phiAngles] = convertCartesianToPolar(xPos, yPos, zPos)
        thetaAngles = atan(sqrt(xPos.^2+yPos.^2)./zPos);
        phiAngles = atan(yPos./xPos);
        
        thetaAngles = thetaAngles*180/pi;
        phiAngles = phiAngles*180/pi;
        phiAngles(xPos<0) = phiAngles(xPos<0) + 180;
        
        thetaAngles(isnan(thetaAngles)) = 0;
        phiAngles(isnan(phiAngles)) = 0;
    end



    %Calculate steering vector for various angles
    function [e, kx, ky] = steeringVector(xPos, yPos, f, c, thetaAngles, phiAngles)
              
        %Change from degrees to radians
        thetaAngles = thetaAngles*pi/180;
        phiAngles = phiAngles*pi/180;
        
        %Wavenumber
        k = 2*pi*f/c;
        
        %Number of elements/sensors in the array
        P = size(xPos,2);
        
        %Changing wave vector to spherical coordinates
        kx = sin(thetaAngles).*cos(phiAngles);
        ky = sin(thetaAngles).*sin(phiAngles);
        
        %Calculate steering vector/matrix
        kxx = bsxfun(@times,kx,reshape(xPos,P,1));
        kyy = bsxfun(@times,ky,reshape(yPos,P,1));
        e = exp(1j*k*(kxx+kyy));
        
    end



    %Generate input signal to all sensors
    function inputSignal = createSignal(xPos, yPos, f, c, fs, xPosSource, yPosSource, zPosSource, amplitudes)
       
        %Get arrival angles from/to sources
        [thetaArrivalAngles, phiArrivalAngles] = convertCartesianToPolar(xPosSource, yPosSource, zPosSource);
        
        %Number of samples to be used
        nSamples = 1e3;
        
        T = nSamples/fs;
        t = 0:1/fs:T-1/fs;
        
        inputSignal = 0;
        for source = 1:numel(thetaArrivalAngles)
            
            %Calculate direction of arrival for the signal for each sensor
            doa = steeringVector(xPos, yPos, f, c, thetaArrivalAngles(source), phiArrivalAngles(source));
            
            %Generate the signal at each microphone
            signal = 10^(amplitudes(source)/20)*doa*exp(1j*2*pi*(f*t+randn(1,nSamples)));
            
            %Total signal equals sum of individual signals
            inputSignal = inputSignal + signal;
        end
        
    end

        
        
        
    %Calculate delay-and-sum power at scanning points
    function S = calculateSteeredResponse(xPos, yPos, w, inputSignal, f, c, scanningPointsX, scanningPointsY, distanceToScanningPlane, numberOfScanningPointsX, numberOfScanningPointsY)
        
        nSamples = numel(inputSignal);
        nSensors = numel(xPos);
        
        %Get scanning angles from scanning points
        [thetaScanningAngles, phiScanningAngles] = convertCartesianToPolar(scanningPointsX, scanningPointsY, distanceToScanningPlane);

        %Get steering vector to each point
        e = steeringVector(xPos, yPos, f, c, thetaScanningAngles, phiScanningAngles);
        
        % Multiply input signal by weighting vector
        inputSignal = diag(w)*inputSignal;
        
        if strcmp('DAS', algorithm)
            % Multiply input signal by weighting vector
            inputSignal = diag(w)*inputSignal;
            
            %Calculate correlation matrix
            R = inputSignal*inputSignal';
            R = R/nSamples;
            useDAS = 1;
        else
            %Calculate correlation matrix
            R = inputSignal*inputSignal';
            R = R + trace(R)/(nSensors^2)*eye(nSensors, nSensors);
            R = R/nSamples;
            R = inv(R);
            useDAS = 0;
        end
        
        %Calculate power as a function of steering vector/scanning angle
        %with either delay-and-sum or minimum variance algorithm
        S = zeros(numberOfScanningPointsY,numberOfScanningPointsX);
        for scanningPointY = 1:numberOfScanningPointsY
            for scanningPointX = 1:numberOfScanningPointsX
                ee = e(:,scanningPointX+(scanningPointY-1)*numberOfScanningPointsX);
                if useDAS
                    S(scanningPointY,scanningPointX) = ee'*R*ee;
                else
                    S(scanningPointY,scanningPointX) = 1./(ee'*R*ee);
                end
            end
        end
        
        %Interpolate for higher resolution
        interpolationFactor = 4;
        interpolationMethod = 'spline';
        
        S = interp2(S, interpolationFactor, interpolationMethod);
        
        S = abs(S)/max(max(abs(S)));
        S = 10*log10(S);
    end





    %Plot the image with overlaid steered response power
    function plotImage(imageFile, S, amplitudes, xPosSource, yPosSource, scanningPointsX, scanningPointsY, maxScanningPlaneExtentX, maxScanningPlaneExtentY)

        fig = figure;
        fig.Name = 'Acoustic camera test';
        fig.NumberTitle = 'off';
        fig.ToolBar = 'none';
        fig.MenuBar = 'none';
        fig.Color = [0 0 0];
        fig.Resize = 'off';
        
        ax = axes;
        
        %Background image
        imagePlot = image(scanningPointsX, scanningPointsY, imageFile);
        hold on
        
        %Coloring of sources
        steeredResponsePlot = imagesc(scanningPointsX, scanningPointsY, S);
        steeredResponsePlot.AlphaData = 0.4;
        cmap = colormap;
        cmap(1,:) = [1 1 1]*0.8;
        colormap(cmap);
        
        %Axes
        axis(ax, 'xy', 'equal')
        box(ax, 'on')    
        xlabel(ax, ['Frequency: ' sprintf('%0.1f', f*1e-3) ' kHz'],'fontweight','normal')
        ylim(ax, [-maxScanningPlaneExtentY maxScanningPlaneExtentY])
        xlim(ax, [-maxScanningPlaneExtentX maxScanningPlaneExtentX])
        ax.Color = [0 0 0];
        ax.XColor = [1 1 1];
        ax.YColor = [1 1 1];
        ax.XTick = [];
        ax.YTick = [];
        
        %Context menu to change frequency, background color and array
        cmFigure = uicontextmenu;
        topMenuArray = uimenu('Parent', cmFigure, 'Label', 'Array');
        topMenuAlgorithm = uimenu('Parent', cmFigure, 'Label', 'Algorithm');
        topMenuTheme = uimenu('Parent', cmFigure, 'Label', 'Background');
        
                     
        %Array
        uimenu('Parent', topMenuArray, 'Label', 'Nor848A-4', 'Callback',{ @changeArray, 'Nor848A-4', steeredResponsePlot });
        uimenu('Parent', topMenuArray, 'Label', 'Nor848A-10', 'Callback',{ @changeArray, 'Nor848A-10', steeredResponsePlot });
        uimenu('Parent', topMenuArray, 'Label', 'Nor848A-10-ring', 'Callback',{ @changeArray, 'Nor848A-10-ring', steeredResponsePlot });
        uimenu('Parent', topMenuArray, 'Label', 'Ring-48', 'Callback',{ @changeArray, 'Ring-48', steeredResponsePlot });
        uimenu('Parent', topMenuArray, 'Label', 'Ring-72', 'Callback',{ @changeArray, 'Ring-72', steeredResponsePlot });
        
        %Algorithm
        uimenu('Parent', topMenuAlgorithm, 'Label', 'Delay-and-sum', 'Callback',{ @changeAlgorithm, 'DAS', steeredResponsePlot });
        uimenu('Parent', topMenuAlgorithm, 'Label', 'Minimum variance', 'Callback',{ @changeAlgorithm, 'MV', steeredResponsePlot });
        
        %Theme
        uimenu('Parent', topMenuTheme, 'Label', 'Color', 'Callback',{ @changeBackgroundColor, 'color', imagePlot });
        uimenu('Parent', topMenuTheme, 'Label', 'Gray', 'Callback',{ @changeBackgroundColor, 'gray', imagePlot });
        
        steeredResponsePlot.UIContextMenu = cmFigure;
        
        
        %Plot sources with context menu (to enable/disable and change power)
        for sourceNumber = 1:numel(amplitudes)
            sourcePlot(sourceNumber) = scatter(xPosSource(sourceNumber), yPosSource(sourceNumber),300, [1 1 1]*0.4);
            
            cmSourcePower = uicontextmenu;
            if amplitudes(sourceNumber) == -100
                uimenu('Parent',cmSourcePower,'Label','enable','Callback', { @changeDbOfSource, 'enable', sourceNumber, steeredResponsePlot, sourcePlot });
            else
                uimenu('Parent',cmSourcePower,'Label','disable','Callback', { @changeDbOfSource, 'disable', sourceNumber, steeredResponsePlot, sourcePlot });
                for dBVal = [-10 -5 -4 -3 -2 -1 1 2 3 4 5 10]
                    if dBVal > 0
                        uimenu('Parent',cmSourcePower,'Label',['+' num2str(dBVal) 'dB'],'Callback', { @changeDbOfSource, dBVal, sourceNumber, steeredResponsePlot });
                    else
                        
                        uimenu('Parent',cmSourcePower,'Label',[num2str(dBVal) 'dB'],'Callback', { @changeDbOfSource, dBVal, sourceNumber, steeredResponsePlot });
                    end
                end
            end
            sourcePlot(sourceNumber).UIContextMenu = cmSourcePower;
        end
              
        maxDynamicRange = 60;
        defaultDisplayValue = 10;
        range = [0.01 maxDynamicRange];
        caxis(ax, [-defaultDisplayValue 0])
        
        title(ax, ['Dynamic range: ' sprintf('%0.2f', defaultDisplayValue) ' dB'], 'FontWeight', 'normal','Color',[1 1 1]);
        
        %Add dynamic range slider
        dynamicRangeSlider = uicontrol('style', 'slider', ...
            'Units', 'normalized',...
            'position', [0.92 0.18 0.03 0.6],...
            'value', log10(defaultDisplayValue),...
            'min', log10(range(1)),...
            'max', log10(range(2)));
        addlistener(dynamicRangeSlider,'ContinuousValueChange',@(hObject, eventdata) caxis(ax, [-10^hObject.Value 0]));
        addlistener(dynamicRangeSlider,'ContinuousValueChange',@(hObject, eventdata) title(ax, ['Dynamic range: ' sprintf('%0.2f', 10^hObject.Value) ' dB'],'fontweight','normal'));
        
        
        %Add frequency slider
        frequencySlider = uicontrol('style', 'slider', ...
            'Units', 'normalized',...
            'position', [0.13 0.03 0.78 0.04],...
            'value', f,...
            'min', 0.1e3,...
            'max', 20e3);
        addlistener(frequencySlider, 'ContinuousValueChange', @(obj,evt) changeFrequencyOfSource(obj, evt, obj.Value, steeredResponsePlot) );
        addlistener(frequencySlider,'ContinuousValueChange',@(obj,evt) xlabel(ax, ['Frequency: ' sprintf('%0.1f', obj.Value*1e-3) ' kHz'],'fontweight','normal'));
        
    end




    function changeDbOfSource(~, ~, dBVal, sourceClicked, steeredResponsePlot, sourcePlot)
        
        %Generate a new context menu for the source if it is
        %enabled/disabled
        if ischar(dBVal)
            
            cmSourcePower = uicontextmenu;
            if strcmp(dBVal,'enable')
                amplitudes(sourceClicked) = 0;
                uimenu('Parent',cmSourcePower,'Label','disable','Callback', { @changeDbOfSource, 'disable', sourceClicked, steeredResponsePlot, sourcePlot });
                for dBVal = [-10 -5 -4 -3 -2 -1 1 2 3 4 5 10]
                    if dBVal > 0
                        uimenu('Parent',cmSourcePower,'Label',['+' num2str(dBVal) 'dB'],'Callback', { @changeDbOfSource, dBVal, sourceClicked, steeredResponsePlot, sourcePlot  });
                    else
                        
                        uimenu('Parent',cmSourcePower,'Label',[num2str(dBVal) 'dB'],'Callback', { @changeDbOfSource, dBVal, sourceClicked, steeredResponsePlot, sourcePlot  });
                    end
                end
            else
                amplitudes(sourceClicked) = -100;
                uimenu('Parent',cmSourcePower,'Label','enable','Callback', { @changeDbOfSource, 'enable', sourceClicked, steeredResponsePlot, sourcePlot });
            end
            sourcePlot(sourceClicked).UIContextMenu = cmSourcePower;
            
        else
            amplitudes(sourceClicked) = amplitudes(sourceClicked)+dBVal;
        end
        
        inputSignal = createSignal(xPos, yPos, f, c, fs, xPosSource, yPosSource, zPosSource, amplitudes);
        S = calculateSteeredResponse(xPos, yPos, w, inputSignal, f, c, scanningPointsX, scanningPointsY, distanceToScanningPlane, numberOfScanningPointsX, numberOfScanningPointsY);
        steeredResponsePlot.CData = S;
    end


    function changeAlgorithm(~, ~, selectedAlgorithm, steeredResponsePlot)
        algorithm = selectedAlgorithm;
        S = calculateSteeredResponse(xPos, yPos, w, inputSignal, f, c, scanningPointsX, scanningPointsY, distanceToScanningPlane, numberOfScanningPointsX, numberOfScanningPointsY);
        steeredResponsePlot.CData = S;
    end

    function changeFrequencyOfSource(~, ~, selectedFrequency, steeredResponsePlot)
        
        f = selectedFrequency;
        inputSignal = createSignal(xPos, yPos, f, c, fs, xPosSource, yPosSource, zPosSource, amplitudes);
        S = calculateSteeredResponse(xPos, yPos, w, inputSignal, f, c, scanningPointsX, scanningPointsY, distanceToScanningPlane, numberOfScanningPointsX, numberOfScanningPointsY);
        steeredResponsePlot.CData = S;
    end



    function changeBackgroundColor(~, ~, color, imagePlot)
        
        if strcmp(color, 'color')
            imagePlot.CData = imageFileColor;
        else
            imagePlot.CData = imageFileGray;
        end
    end



    function changeArray(~, ~, arrayClicked, steeredResponsePlot)
        
        if strcmp(arrayClicked,'Nor848A-10-ring')
            array = load('data/arrays/Nor848A-10.mat');
            xPos = array.xPos(225:256);
            yPos = array.yPos(225:256);
            w = ones(1,32)/32;
        else
            array = load(['data/arrays/' arrayClicked '.mat']);
            if strcmp(arrayClicked,'Nor848A-4') || strcmp(arrayClicked,'Nor848A-10')
                w = array.hiResWeights;
            else
                w = array.w;
            end
            xPos = array.xPos;
            yPos = array.yPos;
        end

        inputSignal = createSignal(xPos, yPos, f, c, fs, xPosSource, yPosSource, zPosSource, amplitudes);
        S = calculateSteeredResponse(xPos, yPos, w, inputSignal, f, c, scanningPointsX, scanningPointsY, distanceToScanningPlane, numberOfScanningPointsX, numberOfScanningPointsY);
        steeredResponsePlot.CData = S;
    end


end