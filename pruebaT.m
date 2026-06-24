clc;
clear;
close all;

carpeta_salida = "F:\Prueba T RS Paper";

% Create folder automaticaly in case it does not exist
if ~exist(carpeta_salida, 'dir')
    mkdir(carpeta_salida);
end


% ==========================================
% PHASE 1: LOAD COMPONENTS
% ==========================================
directorio_principal = "F:\Prueba T RS Paper\Pacientes";

% Define components of interest
NW_componente = [24, 44];
OB_componente = [44, 23];
Componentes = {NW_componente, OB_componente};

% Read Folders
contenido = dir(directorio_principal);
carpetas = contenido([contenido.isdir] & ~ismember({contenido.name}, {'.', '..'}));

% Structure to save data
datos_imagenes = struct();
info_base = []; % Structure to load metadadata NIfTI

% ==========================================
% PHASE 2: OBTAINING ICA COMPONENTS AND CREATING 4D
% ==========================================
for i = 1:length(carpetas)
    nombre_carpeta = carpetas(i).name;
    ruta_carpeta = fullfile(directorio_principal, nombre_carpeta);
    
    comps_actuales = Componentes{i};
    num_comps = length(comps_actuales);
    
    % Search NIfTI files
    archivos_nii = dir(fullfile(ruta_carpeta, '*.nii'));
    archivos_niigz = dir(fullfile(ruta_carpeta, '*.nii.gz'));
    archivos_nifti = [archivos_nii; archivos_niigz]; 
    
    % Start temporal accumulator
    temp_acumulador = cell(1, num_comps);
    
    % Iteration on patients
    for j = 1:length(archivos_nifti)
        nombre_archivo = archivos_nifti(j).name;
        ruta_archivo = fullfile(ruta_carpeta, nombre_archivo);
        
        % Charge volumes 
        volumen = niftiread(ruta_archivo);
        
        % Capture metadata
        if isempty(info_base)
            info_base = niftiinfo(ruta_archivo);
        end
        
        % Extract and pile components of interest
        for k = 1:num_comps
            idx_componente = comps_actuales(k);
            vol_3D = volumen(:, :, :, idx_componente);
            temp_acumulador{k} = cat(4, temp_acumulador{k}, vol_3D);
        end
    end
    
    % Dynamic storing of the final structure
    nombre_valido = matlab.lang.makeValidName(nombre_carpeta);
    for k = 1:num_comps
        idx_componente = comps_actuales(k);
        nombre_campo = sprintf('comp_%d', idx_componente); 
        datos_imagenes.(nombre_valido).(nombre_campo) = temp_acumulador{k};
    end
end

% ==========================================
% PHASE 3: EQUALIZE NUMBER OF COMPONENTS
% ==========================================
C_NW = struct2cell(datos_imagenes.Normopeso);
C_OB = struct2cell(datos_imagenes.Obesos);
num_NW = length(C_NW);
num_OB = length(C_OB);

if num_NW ~= num_OB
    dif = num_NW - num_OB;
    if dif > 0
        target_len = num_OB;
        for k = (target_len + 1) : num_NW
            C_NW{target_len} = C_NW{target_len} + C_NW{k};
        end
        C_NW = C_NW(1:target_len);
    elseif dif < 0
        target_len = num_NW;
        for k = (target_len + 1) : num_OB
            C_OB{target_len} = C_OB{target_len} + C_OB{k};
        end
        C_OB = C_OB(1:target_len);
    end
end

% ==========================================
% PHASE 4: 4D VOXELWISE T-TEST
% ==========================================
num_componentes_final = length(C_OB);
mapas_p = cell(num_componentes_final, 1);
mapas_t = cell(num_componentes_final, 1);

fprintf('\nCalculating t test voxelwise for %d components...\n', num_componentes_final);

for i = 1 : num_componentes_final 
    % Obtain p_map 
    [~, p_map, ~, stats] = ttest2(C_NW{i,1}, C_OB{i,1}, 'Dim', 4);
    
    % Clean background
    p_map(isnan(p_map)) = 1; 
    t_map = stats.tstat;
    t_map(isnan(t_map)) = 0;
    
    % Save final maps. 
    mapas_p{i} = p_map;
    mapas_t{i} = t_map;
end

% ========================================================
% PHASE 5: EXPORT NIfTI
% ========================================================
fprintf('Exporting T maps in NIfTI format preserving dimensions...\n');

info_salida = info_base;
info_salida.Datatype = 'double'; 
info_salida.ImageSize = size(mapas_p{1}); 
info_salida.PixelDimensions = info_base.PixelDimensions(1:3); 

for i = 1 : length(mapas_p)
    nombre_archivo = sprintf('mapa_t_component_%d.nii', i);
    ruta_completa_salida = fullfile(carpeta_salida, nombre_archivo);
    
    
    matriz_double = double(mapas_t{i});
    
    % Save file in a given root.
    niftiwrite(matriz_double, ruta_completa_salida, info_salida);
    fprintf(' -> Saved correctly in: %s\n', ruta_completa_salida);
end



fprintf('\n¡Pipeline executed successfully!\n');