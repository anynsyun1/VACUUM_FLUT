// cpp_backend/vacuum_backend.h
// vacuum_backend.h

// vacuum_backend.h
#pragma once

#include <vector>
#include <string>
#include<math.h>
#include "vacuum_device.h"

#define MAXAVG 5
// #define STARTOFFSET 7
#define DIV 2

#define MAXTIME 65535
// vacuum_backend.h 
static int MAXPRESS=67;
static int MINPRESS=62;
static float MINDIFF=1.0;
static float hrate = 0.5;
static int STARTOFFSET = 7;



extern "C" {

struct VacuumMeasureResult {
    float pressure;      // 
    float startPressure;      // 
    float stopPressure;      // 
    float diffPressure;  // 
    int   pass;          // 1=PASS, 0=FAIL
    int   stop;          // 
    int   ok;            // 
};

#if defined(_WIN32)
  #define EXPORT __declspec(dllexport)
#else
  #define EXPORT __attribute__((visibility("default")))
#endif
 EXPORT VacuumMeasureResult vacuum_measure_decide(int channel, int counter);

} // extern "C"

class VacuumBackend
{
public:
    static VacuumBackend& instance();

    // 
    void setTimeMode(int mode);
    void setPressureMode(int kpa);

    void start();   // Flutter
    void step();    // Flutter 

    float lastPressure() const { return lastPressure_; }
    bool  lastPass() const { return lastPass_; }

    // ---
    void refreshPorts();
    int  portCount() const;
    const char* portName(int index) const;

    bool connectToPort(const char* portName);
    void disconnect();
    bool isConnected() const;

    // 
    bool measureOnceInternal(int channel, float& outPressure);
    // channel: outPressure:, cnt:, 
    bool measureAndDecide(int channel, int counter, float& outPressure, float& pSt, float& pSp,  float& diffPressure, bool& pf, bool& sp);



private:
    VacuumBackend();
    ~VacuumBackend();

    VacuumBackend(const VacuumBackend&) = delete;
    VacuumBackend& operator=(const VacuumBackend&) = delete;

    float averaging(float vacarr[], float val,  unsigned int *idx);
    void clearAveraging(float vacarr1[], float vacarr2[], unsigned int *idx );

private:
    // 
    std::vector<std::string> ports_;

    // 
    VacuumDevice device_;

    //
    bool        connected_       = false;
    std::string currentPortName_;

    // 
    int timeMode_    = 0;  // 1:
    int pressureSet_ = 0;  // 

    // 
    int configuredDuration_ = 0;   // 
    int elapsedSteps_       = 0;   // 

    // 
    float lastPressure_ = 0.0f;
    bool  lastPass_     = true;

    int flag=0;
    int comflag=0;
    int rcvdflag = 0;

    float startpress = 0.0;

    float st_avgpress[MAXAVG] = {0.0, 0.0, 0.0, 0.0, 0.0};
    float sp_avgpress[MAXAVG] = {0.0, 0.0, 0.0, 0.0, 0.0};

    unsigned int stcnt=0;
    unsigned int spcnt=0;
    unsigned int *stcntPtr=&stcnt;
    unsigned int *spcntPtr=&spcnt;

    float stoppress=0.0;
    float offsetpress = 0.0;

};
