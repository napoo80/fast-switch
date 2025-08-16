# ⚡ Setup Rápido para Testing - FastSwitch

## 🎯 Objetivo: Probar todas las funciones en 5 minutos

### 1. **Modificaciones Temporales para Testing**

Abre `AppDelegate.swift` y cambia estas líneas:

#### **A. Acelerar Wellness Questions (línea ~956)**
```swift
// CAMBIAR ESTA LÍNEA:
wellnessQuestionTimer = Timer.scheduledTimer(withTimeInterval: 1800, repeats: true)
// POR ESTA:
wellnessQuestionTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) // 30 segundos
```

#### **B. Acelerar Preguntas de Mate (línea ~1024)**  
```swift
// CAMBIAR ESTA LÍNEA:
return timeSinceLastQuestion >= 7200 // 2 hours
// POR ESTA:
return timeSinceLastQuestion >= 60 // 1 minuto
```

#### **C. Permitir Exercise Questions a cualquier hora (línea ~1033)**
```swift
// CAMBIAR ESTA LÍNEA:
guard hour >= 14 && hour <= 16 else { return false }
// POR ESTA:
guard hour >= 9 && hour <= 23 else { return false } // 9AM-11PM
```

#### **D. Acelerar Energy Check (línea ~1048)**
```swift
// CAMBIAR ESTA LÍNEA:
guard sessionDuration >= 7200 else { return false } // 2+ hours
// POR ESTA:  
guard sessionDuration >= 30 else { return false } // 30 segundos
```

### 2. **Testing Rápido (5 minutos)**

1. **Compilar y ejecutar** (⌘R en Xcode)
2. **Esperar 30 segundos** → Primera notificación de mate
3. **Responder** con cualquier opción → Ver logs
4. **Esperar 1 minuto** → Notificación de ejercicio  
5. **Esperar 30 segundos más** → Energy check
6. **Menu bar** → `📊 Reportes` → `💾 Exportar Datos`

### 3. **Verificar Logs en Xcode Console**
Busca estos mensajes:
```
🌱 FastSwitch: Sistema de bienestar inicializado
💡 FastSwitch: Frases cargadas desde archivo externo - 23 frases
🧉 FastSwitch: Pregunta de mate enviada
🧉 FastSwitch: Mate registrado - Cantidad: 1, Azúcar: 0
🏃 FastSwitch: Pregunta de ejercicio enviada  
⚡ FastSwitch: Check de energía enviado
```

### 4. **Testing de Frases**
Edita `/Users/gaston/code/repos/fast-switch/phrases.json` y agrega:
```json
{
  "id": "quick_test",
  "category": "testing",
  "text": "🧪 TESTING MODE ACTIVADO - Si ves esto, las frases funcionan!",
  "contexts": ["afternoon", "mate_check", "energy_check"],
  "weight": 99.0
}
```

### 5. **Restaurar Configuración Normal**
Después del testing, revierte los cambios:
- 1800 segundos (30 min) para wellness timer
- 7200 segundos (2 horas) para mate questions  
- hour >= 14 && hour <= 16 para exercise
- sessionDuration >= 7200 para energy check

## 🚨 **Script de Testing Automatizado**

Si quieres ser más eficiente, aquí hay un script que puedes pegar temporalmente:

```swift
// PEGAR AL FINAL DE applicationDidFinishLaunching (SOLO PARA TESTING)
#if DEBUG
DispatchQueue.main.asyncAfter(deadline: .now() + 5) { self.testAllFeatures() }
#endif
```

Y agregar este método al final de la clase:

```swift
#if DEBUG
private func testAllFeatures() {
    print("🧪 INICIANDO TESTING AUTOMATIZADO")
    
    // Test mate question
    DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
        self.askMateQuestion()
    }
    
    // Test exercise question  
    DispatchQueue.main.asyncAfter(deadline: .now() + 8) {
        self.askExerciseQuestion()
    }
    
    // Test energy check
    DispatchQueue.main.asyncAfter(deadline: .now() + 14) {
        self.askEnergyCheck()
    }
    
    // Auto-export data
    DispatchQueue.main.asyncAfter(deadline: .now() + 20) {
        self.saveTodayData()
        print("🧪 Testing completado - Datos guardados")
    }
}
#endif
```

**⚠️ RECORDATORIO**: Eliminar el código de testing antes de usar en producción!