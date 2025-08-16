# 🧪 Guía de Testing - FastSwitch Sistema de Bienestar

## 🚀 Preparación para Testing

### 1. **Compilar y Ejecutar**
```bash
cd /Users/gaston/code/repos/fast-switch/FastSwitch
open FastSwitch.xcodeproj

# En Xcode: Product → Run (⌘R)
# O compilar con xcodebuild si tienes Xcode tools
```

### 2. **Verificar Permisos**
Al ejecutar por primera vez, asegúrate de conceder:
- ✅ **Accessibility**: Para hotkeys globales
- ✅ **Automation**: Para controlar otras apps  
- ✅ **Notifications**: Para mostrar preguntas de bienestar

### 3. **Activar Modo Testing**
La app auto-activa el modo testing con intervalos de:
- 📢 **1 minuto**: Primera notificación de descanso
- 📢 **5 minutos**: Segunda notificación  
- 📢 **10 minutos**: Tercera notificación

## 🧉 **Testing del Sistema de Mate y Azúcar**

### Trigger Manual (Para Testing Rápido)
Las preguntas de mate se activan automáticamente cada 2 horas entre 9AM-6PM, pero puedes forzar el testing:

1. **Modificar Intervalos** (temporal para testing):
   ```swift
   // En askMateQuestion(), cambiar el intervalo
   return timeSinceLastQuestion >= 120 // 2 minutos en lugar de 2 horas
   ```

2. **Testing Manual**:
   - ⏰ Esperar 2 minutos después de iniciar la app
   - 📱 Debería aparecer: "🧉 Check de Mate y Azúcar"
   - 🔲 Probar cada botón:
     - `🧉 Ninguno` → Registra 0 mates, 0 azúcar
     - `🧉 1-2 sin/poco` → Registra 1 mate, sin azúcar  
     - `🧉 3-4 normal` → Registra 2 mates, azúcar normal
     - `🧉 5+ dulce` → Registra 3 mates, azúcar alto

### Verificar Registro
Revisa los logs en Xcode Console:
```
🧉 FastSwitch: Mate registrado - Cantidad: 2, Azúcar: 1
```

## 🏃 **Testing del Sistema de Ejercicio**  

### Activación
- 🕐 **Horario**: 2PM - 4PM (solo una vez por día)
- 📱 **Notificación**: "🏃 Check de Ejercicio"

### Testing Manual (Para acelerar)
```swift
// En shouldAskExerciseQuestion(), cambiar condición:
guard hour >= 10 && hour <= 23 else { return false } // Cualquier hora después de 10AM
```

### Botones de Prueba
- `❌ No` → Sin ejercicio
- `🚶 15min` → Ejercicio ligero
- `🏃 30min` → Ejercicio moderado  
- `💪 45min+` → Ejercicio intenso

## ⚡ **Testing del Sistema de Energía**

### Trigger Automático
- ⏰ **Condición**: Después de 2+ horas de trabajo continuo
- 📱 **Notificación**: "⚡ Check de Energía"

### Testing Manual (Acelerar)
```swift
// En shouldAskEnergyCheck(), cambiar:
guard sessionDuration >= 300 else { return false } // 5 minutos en lugar de 2 horas
```

### Botones de Prueba  
- `🔋 Bajo (1-3)` → Energía baja
- `🔋 Medio (4-6)` → Energía media
- `🔋 Alto (7-10)` → Energía alta

## 💡 **Testing del Sistema de Frases**

### Verificación de Carga
Revisar logs al iniciar:
```
💡 FastSwitch: Frases cargadas desde archivo externo - 23 frases
```

### Testing de Frases Contextuales
1. **Editar phrases.json** (agregar frase de prueba):
   ```json
   {
     "id": "test_phrase",
     "category": "testing", 
     "text": "FRASE DE PRUEBA - Si ves esto, funciona!",
     "contexts": ["afternoon", "mate_check"],
     "weight": 10.0
   }
   ```

2. **Reiniciar la app** → Debería cargar la nueva frase
3. **Triggerar notificación** → Buscar "FRASE DE PRUEBA" en el contenido

### Testing de Fallback
1. **Renombrar phrases.json** → phrases_backup.json
2. **Reiniciar app** → Debería usar frases por defecto
3. **Ver logs**: "💡 FastSwitch: Usando frases por defecto - 5 frases"

## 📊 **Testing de Almacenamiento y Exportación**

### Verificar Almacenamiento
```bash
# Ver datos almacenados en UserDefaults
defaults read com.yourcompany.FastSwitch FastSwitchUsageHistory
```

### Testing de Exportación
1. **Menu Bar** → `📊 Reportes` → `💾 Exportar Datos`
2. **Guardar archivo JSON**
3. **Verificar contenido**:
   ```json
   {
     "dailyData": {
       "2024-08-14": {
         "wellnessMetrics": {
           "mateAndSugarRecords": [...],
           "exerciseRecords": [...],
           "energyLevels": [...]
         }
       }
     }
   }
   ```

## 🕐 **Testing de Detección de Jornada**

### Inicio de Jornada
- ✅ **Auto-detectado** al primer uso del día
- 📝 **Log esperado**: "🌅 FastSwitch: Inicio de jornada registrado"

### Verificar Timestamp
En datos exportados buscar:
```json
"workdayStart": "2024-08-14T09:15:00Z"
```

## 🔔 **Testing de Debug y Monitoreo**

### Logs de Debug Activados
Al estar en modo testing, verás logs cada 5 segundos:
```
⏰ FastSwitch: Sesión actual: 180s (3min)
🔔 DEBUG: Próxima notificación #1 en 2:30 (intervalo: 5min)
📊 DEBUG: Progreso [██████░░░░░░░░░░░░░░] 30%
🌱 FastSwitch: Sistema de bienestar inicializado
```

### Monitorear Wellness Questions
```
🌱 FastSwitch: Checking wellness questions...
🧉 FastSwitch: Should ask mate question: true
☕ FastSwitch: Pregunta de mate enviada
```

## 🧪 **Plan de Testing Completo (30 minutos)**

### **Fase 1: Setup (5 min)**
1. ✅ Compilar y ejecutar
2. ✅ Conceder permisos
3. ✅ Verificar logs iniciales
4. ✅ Confirmar carga de frases

### **Fase 2: Testing de Notificaciones (20 min)**
1. 🧉 **Mate Question** (esperar 2 min o modificar código)
   - Probar cada botón
   - Verificar logs de registro
2. 🏃 **Exercise Question** (cambiar horario o esperar 2PM)
   - Probar diferentes intensidades  
3. ⚡ **Energy Check** (trabajar 2+ horas o modificar código)
   - Probar niveles de energía
4. 📝 **Daily Reflection** (5PM-8PM o modificar detectEndOfWorkday())
   - Probar botones rápidos de mood
   - Probar interfaz completa de bitácora
   - Verificar análisis automático de texto

### **Fase 3: Testing de Sistema (10 min)**
1. 📊 **Exportar datos** y verificar JSON
2. 💡 **Editar phrases.json** y probar nueva frase
3. 🔄 **Reiniciar app** y verificar persistencia
4. 📈 **Revisar reportes** semanales/anuales

## ⚠️ **Modificaciones Para Testing Rápido**

Si quieres acelerar el testing, modifica temporalmente:

```swift
// Wellness questions cada 30 segundos en lugar de 30 minutos
wellnessQuestionTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true)

// Preguntas de mate cada 2 minutos en lugar de 2 horas  
return timeSinceLastQuestion >= 120

// Energy check después de 1 minuto en lugar de 2 horas
guard sessionDuration >= 60 else { return false }

// Exercise questions cualquier hora
guard hour >= 9 && hour <= 23 else { return false }

// Daily reflection testing - cualquier hora con sesión corta
guard hour >= 10 && hour <= 23 else { return false } // En detectEndOfWorkday()
guard sessionDuration >= 300 else { return false } // 5 minutos
```

## 📝 **Testing del Sistema de Reflexión Diaria**

### Activación Automática
- ⏰ **Horario**: 5PM - 8PM 
- 📊 **Condición**: Sesión de 4+ horas
- 🔄 **Frecuencia**: Solo una vez por día

### Opciones de Reflexión
1. **Botones Rápidos**
   - `💪 Productivo` → Mood productivo
   - `⚖️ Equilibrado` → Mood balanceado  
   - `😴 Cansado` → Mood cansado
   - `😤 Estresado` → Mood estresado

2. **Interfaz de Bitácora Completa**
   - `✍️ Escribir Bitácora` → Abre diálogo de texto
   - Análisis automático de sentimientos
   - Almacenamiento en datos de bienestar

### Testing de Análisis de Texto
Prueba escribir estos textos para verificar la detección automática de mood:

**Para mood "productive":**
- "Hoy logré completar todos mis objetivos"
- "Fue un día muy productivo y eficiente"

**Para mood "stressed":**  
- "Me sentí estresado por la presión del trabajo"
- "Fue un día con mucha ansiedad"

**Para mood "tired":**
- "Estoy muy cansado y agotado"
- "Sin energía para seguir trabajando"

## 📱 **Testing en Producción**

Para testing real (sin modificaciones):
1. 🌅 **Mañana**: Iniciar la app, trabajar normalmente
2. 🕙 **10AM**: Primera pregunta de mate
3. 🕐 **12PM**: Segunda pregunta de mate  
4. 🕑 **2PM**: Pregunta de ejercicio
5. 🕒 **3PM**: Tercera pregunta de mate (si has trabajado 2+ horas seguidas)
6. 🕘 **6PM**: Check de energía automático

## 🐛 **Troubleshooting**

### No aparecen notificaciones
- ✅ Verificar permisos de notificaciones
- ✅ Revisar modo "Do Not Disturb"
- ✅ Confirmar que la app esté ejecutándose

### No se cargan frases personalizadas  
- ✅ Verificar formato JSON válido
- ✅ Confirmar ruta del archivo phrases.json
- ✅ Revisar logs de carga

### Datos no se exportan
- ✅ Verificar que hay datos del día actual
- ✅ Confirmar permisos de escritura
- ✅ Probar diferentes ubicaciones de guardado

¡Con esta guía puedes probar sistemáticamente todas las funcionalidades del sistema de bienestar! 🚀