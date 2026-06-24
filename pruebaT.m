clc;
clear;
close all;

carpeta_salida = "F:\Prueba T RS Paper";

% Crear la carpeta automáticamente si no existe en el disco
if ~exist(carpeta_salida, 'dir')
    mkdir(carpeta_salida);
end


% ==========================================
% ETAPA 1: CONFIGURACIÓN Y LECTURA DINÁMICA
% ==========================================
directorio_principal = "F:\Prueba T RS Paper\Pacientes";

% Definir componentes de interés
NW_componente = [24, 44];
OB_componente = [44, 23];
Componentes = {NW_componente, OB_componente};

% Obtener carpetas reales (filtrando . y ..)
contenido = dir(directorio_principal);
carpetas = contenido([contenido.isdir] & ~ismember({contenido.name}, {'.', '..'}));

% Estructura para guardar la información organizada en memoria
datos_imagenes = struct();
info_base = []; % Aquí guardaremos el molde de la metadata NIfTI

% ==========================================
% ETAPA 2: EXTRACCIÓN Y APILAMIENTO 4D
% ==========================================
for i = 1:length(carpetas)
    nombre_carpeta = carpetas(i).name;
    ruta_carpeta = fullfile(directorio_principal, nombre_carpeta);
    
    comps_actuales = Componentes{i};
    num_comps = length(comps_actuales);
    
    % Buscar archivos NIfTI
    archivos_nii = dir(fullfile(ruta_carpeta, '*.nii'));
    archivos_niigz = dir(fullfile(ruta_carpeta, '*.nii.gz'));
    archivos_nifti = [archivos_nii; archivos_niigz]; 
    
    % Inicializar acumulador temporal para esta carpeta (bloques 4D)
    temp_acumulador = cell(1, num_comps);
    
    % Iterar sobre los pacientes
    for j = 1:length(archivos_nifti)
        nombre_archivo = archivos_nifti(j).name;
        ruta_archivo = fullfile(ruta_carpeta, nombre_archivo);
        
        % Cargar el volumen 
        volumen = niftiread(ruta_archivo);
        
        % Capturar la metadata del primer paciente como molde espacial
        if isempty(info_base)
            info_base = niftiinfo(ruta_archivo);
        end
        
        % Extraer y apilar las componentes de interés en la 4ta dimensión
        for k = 1:num_comps
            idx_componente = comps_actuales(k);
            vol_3D = volumen(:, :, :, idx_componente);
            temp_acumulador{k} = cat(4, temp_acumulador{k}, vol_3D);
        end
    end
    
    % Guardar dinámicamente en la estructura final
    nombre_valido = matlab.lang.makeValidName(nombre_carpeta);
    for k = 1:num_comps
        idx_componente = comps_actuales(k);
        nombre_campo = sprintf('comp_%d', idx_componente); 
        datos_imagenes.(nombre_valido).(nombre_campo) = temp_acumulador{k};
    end
end

% ==========================================
% ETAPA 3: HOMOLOGACIÓN POR FUSIÓN
% ==========================================
% Forzamos los nombres de los campos que creaste para tus estructuras
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
% ETAPA 4: ANÁLISIS VOXELWISE T-TEST
% ==========================================
num_componentes_final = length(C_OB);
mapas_p = cell(num_componentes_final, 1);
mapas_t = cell(num_componentes_final, 1);

fprintf('\nCalculando prueba t voxelwise para %d componentes...\n', num_componentes_final);

for i = 1 : num_componentes_final 
    % Obtenemos p_map (2a salida) y stats para extraer tstat (4a salida)
    [~, p_map, ~, stats] = ttest2(C_NW{i,1}, C_OB{i,1}, 'Dim', 4);
    
    % Limpiar el fondo (reemplazar NaN)
    p_map(isnan(p_map)) = 1; 
    t_map = stats.tstat;
    t_map(isnan(t_map)) = 0;
    
    % Guardar mapas limpios
    mapas_p{i} = p_map;
    mapas_t{i} = t_map;
end

% ========================================================
% ETAPA 5: EXPORTACIÓN EXACTA A NIfTI (Reemplaza esta etapa)
% ========================================================
fprintf('Exportando mapas P a formato NIfTI preservando dimensiones...\n');

info_salida = info_base;
info_salida.Datatype = 'double'; % El encabezado dice 'double'
info_salida.ImageSize = size(mapas_p{1}); 
info_salida.PixelDimensions = info_base.PixelDimensions(1:3); 

for i = 1 : length(mapas_p)
    nombre_archivo = sprintf('mapa_t_componente_%d.nii', i);
    ruta_completa_salida = fullfile(carpeta_salida, nombre_archivo);
    
    % -----> CLAVE: Forzamos la matriz a 'double' para que coincida con el header
    matriz_double = double(mapas_t{i});
    
    % Guardar el archivo en la ruta específica
    niftiwrite(matriz_double, ruta_completa_salida, info_salida);
    fprintf(' -> Guardado correctamente en: %s\n', ruta_completa_salida);
end



fprintf('\n¡Pipeline ejecutado con éxito!\n');