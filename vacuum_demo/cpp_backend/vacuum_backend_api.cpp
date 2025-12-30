// vacuum_backend_api.cpp
// vacuum_backend_api.cpp

#include "vacuum_backend.h"
#include <cstring>
#include <QtCore/QDebug>

#if defined(_WIN32)
  #define EXPORT __declspec(dllexport)
#else
  #define EXPORT __attribute__((visibility("default")))
#endif

extern "C" {

EXPORT void vacuum_init()
{
    
    (void)VacuumBackend::instance();
    qDebug() << "[C API] vacuum_init()";
}

EXPORT void vacuum_set_time_mode(int mode)
{
    VacuumBackend::instance().setTimeMode(mode);
}

EXPORT void vacuum_set_pressure_mode(int kpa)
{
    VacuumBackend::instance().setPressureMode(kpa);
}


EXPORT void vacuum_start()
{
    VacuumBackend::instance().start();
}

EXPORT void vacuum_step()
{
    VacuumBackend::instance().step();
}


EXPORT float vacuum_get_last_pressure()
{
    return VacuumBackend::instance().lastPressure();
}

// 1 = PASS, 0 = FAIL
EXPORT int vacuum_get_last_pass()
{
    return VacuumBackend::instance().lastPass() ? 1 : 0;
}


EXPORT int vacuum_connect(const char* portName)
{
    return VacuumBackend::instance().connectToPort(portName) ? 1 : 0;
}

EXPORT void vacuum_disconnect()
{
    VacuumBackend::instance().disconnect();
}

EXPORT int vacuum_is_connected()
{
    return VacuumBackend::instance().isConnected() ? 1 : 0;
}

EXPORT int vacuum_list_ports(char* buffer, int bufferSize)
{
    auto& backend = VacuumBackend::instance();
    backend.refreshPorts();

    const int count = backend.portCount();

    std::string joined;
    for (int i = 0; i < count; ++i) {
        const char* name = backend.portName(i);
        if (!name) continue;
        if (!joined.empty())
            joined += ';';
        joined += name;
    }

    if (bufferSize <= 0) {
       
        return static_cast<int>(joined.size() + 1);
    }

    if (static_cast<int>(joined.size() + 1) > bufferSize) {
        return -1;  // 
    }

    std::memcpy(buffer, joined.c_str(), joined.size() + 1);
    return count;
}

EXPORT float vacuum_debug_measure_once(int channel)
{
    float p = 0.0f;
    bool ok = VacuumBackend::instance().measureOnceInternal(channel, p);
    if (!ok) return -1.0f;
    return p;
}

EXPORT float vacuum_debug_measure_once2(int channel, int cnt)
{

    float p = 0.0f;
    float pSt = 0.0f;
    float pSp = 0.0f;
    float diff = 0.0f;
    bool pass = false;
    bool stop = false;

   
    bool ok = VacuumBackend::instance().measureAndDecide(
        channel,
        cnt,
        p,
        pSt,
        pSp,
        diff,
        pass,
        stop
    );

    if (!ok) {
        return -1.0f; 
    }

  
    return p;


}


EXPORT VacuumMeasureResult vacuum_measure_decide(int channel, int counter)
{
    VacuumMeasureResult result{};
    float p = 0.0f;
    float pSt = 0.0f;
    float pSp = 0.0f;
    float diff = 0.0f;
    bool pass = false;
    bool stop = false;

    bool ok = VacuumBackend::instance().measureAndDecide(
        channel,
        counter,
        p,
        pSt,
        pSp,
        diff,
        pass,
        stop
    );

    result.pressure      = p;
    result.startPressure = pSt;
    result.stopPressure  = pSp;
    result.diffPressure  = diff;
    result.pass          = pass ? 1 : 0;
    result.stop          = stop ? 1 : 0;
    result.ok            = ok ? 1 : 0;

    return result;
}

} // extern "C"
