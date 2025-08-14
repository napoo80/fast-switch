# 📊 FastSwitch Usage Analyzer

El `usage_analyzer.py` es una herramienta de análisis externa que procesa los datos exportados de FastSwitch para generar reportes detallados de productividad.

## 🚀 Instalación y Requisitos

### Requisitos
- **Python 3.6+** instalado en tu sistema
- No requiere dependencias externas (usa solo librerías estándar de Python)

### Verificar Python
```bash
python3 --version
# Debería mostrar: Python 3.x.x
```

## 📤 Exportar Datos desde FastSwitch

1. **Abrir FastSwitch** (icono F→ en la barra de menú)
2. **Ir a Reportes** → `📊 Reportes` → `💾 Exportar Datos`
3. **Guardar el archivo JSON** (ej: `FastSwitch-Usage-Data-2024-08-14.json`)

## 🏃‍♂️ Ejecutar el Analizador

### Uso Básico
```bash
cd /path/to/fast-switch
python3 usage_analyzer.py FastSwitch-Usage-Data-2024-08-14.json
```

### Ejemplo Completo
```bash
# Navegar al directorio del proyecto
cd /Users/gaston/code/repos/fast-switch

# Ejecutar análisis
python3 usage_analyzer.py ~/Downloads/FastSwitch-Usage-Data-2024-08-14.json
```

### Opciones Disponibles
```bash
# Ayuda
python3 usage_analyzer.py --help

# Análisis básico
python3 usage_analyzer.py data.json

# Solo resumen (próximamente)
python3 usage_analyzer.py data.json --summary
```

## 📋 Ejemplo de Output

```
📊 FastSwitch Usage Analysis
==================================================

📅 Data Range: 30 days
⏰ Total Work Time: 127h 45m
☕ Total Break Time: 23h 12m
📞 Total Call Time: 45h 30m
📈 Average Daily Work: 4h 15m

📱 Top Applications:
   1. VSCode              : 45h 30m (35.6%)
   2. Chrome              : 32h 15m (25.2%)
   3. Terminal            : 18h 45m (14.7%)
   4. Slack               : 12h 30m (9.8%)
   5. Notion              : 8h 15m (6.5%)

🧘 Deep Focus Statistics:
   Sessions: 25
   Total Time: 18h 45m
   Average Session: 45m

💪 Work Patterns:
   Continuous Sessions: 156
   Longest Session: 2h 30m
   Average Session: 28m

📅 Weekly Patterns:
   Monday   : 5h 30m
   Tuesday  : 4h 45m
   Wednesday: 4h 15m
   Thursday : 4h 30m
   Friday   : 3h 45m
   Saturday : 2h 15m
   Sunday   : 1h 30m
```

## 🔧 Troubleshooting

### Error: "command not found: python3"
```bash
# En macOS, instalar Python:
brew install python3

# O usar python en lugar de python3:
python usage_analyzer.py data.json
```

### Error: "No such file or directory"
```bash
# Verificar que el archivo existe:
ls -la FastSwitch-Usage-Data-*.json

# Usar ruta completa:
python3 usage_analyzer.py /Users/tuusuario/Downloads/FastSwitch-Usage-Data-2024-08-14.json
```

### Error: "Invalid JSON file"
- Asegúrate de exportar los datos correctamente desde FastSwitch
- Verifica que el archivo no esté corrupto
- El archivo debe tener extensión `.json`

## 📊 Tipos de Análisis

### 🎯 Análisis Incluidos
- **Tiempo total de trabajo** por día/semana/mes
- **Top 10 aplicaciones** más usadas con porcentajes
- **Estadísticas de Deep Focus**: sesiones, duración promedio
- **Patrones de trabajo**: sesión más larga, promedio
- **Análisis semanal**: productividad por día de la semana
- **Desglose mensual**: tendencias a largo plazo

### 📈 Métricas Calculadas
- **Tiempo activo total** vs tiempo de descanso
- **Porcentaje de uso** por aplicación
- **Eficiencia de sesiones** de trabajo continuo
- **Patterns de productividad** por día/hora
- **Ratios trabajo/descanso** saludables

## 🔄 Workflow Recomendado

1. **Diario**: Revisar dashboard integrado en FastSwitch
2. **Semanal**: Usar reportes semanales de la app
3. **Mensual**: Exportar datos y ejecutar `usage_analyzer.py`
4. **Análisis profundo**: Usar el analizador para insights detallados

## 🛠️ Personalización

El script es completamente modificable. Puedes:
- Agregar nuevos tipos de análisis
- Cambiar el formato de output
- Integrar con otras herramientas
- Exportar a CSV, Excel, etc.

Para modificar, edita directamente `usage_analyzer.py` - está bien documentado y es fácil de extender.

## 🆘 Soporte

Si tienes problemas:
1. Verifica que Python 3.6+ esté instalado
2. Confirma que el archivo JSON esté bien exportado
3. Revisa los mensajes de error para más detalles
4. El analizador es opcional - FastSwitch funciona perfectamente sin él