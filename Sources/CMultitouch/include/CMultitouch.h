#pragma once
#include <stdbool.h>
#include <stdint.h>

// MultitouchSupport macOS'un belgesiz (private) parçasıdır. Düzen, açık kaynak projelerde
// (OpenMultitouchSupport, MiddleClick) yıllardır kullanılanla aynıdır. Apple değiştirirse bozulabilir.

typedef struct {
    float x, y;
} TMPoint;

typedef struct {
    TMPoint position, velocity;
} TMVector;

/// Tek bir parmağın tek karedeki kaydı.
typedef struct {
    int32_t frame;
    double timestamp;
    int32_t identifier;      // parmak değmeye devam ettikçe aynı kalan numara
    int32_t state;           // 1-2 yaklaşıyor, 3 değdi, 4 basılı, 5 kalkıyor, 6-7 uzaklaşıyor
    int32_t fingerID;
    int32_t handID;
    TMVector normalized;     // 0-1 arası konum: x soldan sağa, y alttan üste
    float size;              // temas büyüklüğü
    int32_t field9;
    float angle;
    float majorAxis;
    float minorAxis;
    TMVector absolute;
    int32_t field14;
    int32_t field15;
    float density;
} TMTouch;

typedef void (*TMFrameCallback)(void *device, const TMTouch *touches, int count, double timestamp);

/// Parçayı yükler; bulunamazsa false.
bool tm_load(void);

/// Çalışan aygıtları durdurur, aygıt listesini yeniden oluşturur ve sayısını döndürür.
int tm_refresh_devices(void);
void *tm_device_at(int index);

/// Yüzey boyu (milimetrenin yüzde biri cinsinden); bilinmiyorsa false.
bool tm_device_size(void *device, int *width, int *height);
bool tm_device_is_builtin(void *device);

/// Her karede çağrılacak fonksiyonu ayarlar (tüm aygıtlar için tek).
void tm_set_callback(TMFrameCallback callback);
void tm_device_start(void *device);
void tm_stop_all(void);
