// cpp_backend/vacuum_backend.cpp

// vacuum_backend.cpp

#include "vacuum_backend.h"

#include <QtCore/QDebug>
#include <QtCore/QString>

// ───────────────────────────────────────
//  Singleton
// ───────────────────────────────────────
VacuumBackend& VacuumBackend::instance()
{
    static VacuumBackend inst;
    return inst;
}

VacuumBackend::VacuumBackend()
{
    refreshPorts();
}

VacuumBackend::~VacuumBackend()
{
    disconnect();
}

void VacuumBackend::setTimeMode(int mode)
{
    timeMode_ = mode;

    switch (mode) {
    case 2: configuredDuration_ = 300; break; // 
    case 3: configuredDuration_ = 180; break; //
    case 4: configuredDuration_ = 120; break; //
    case 5: configuredDuration_ = 30;  break; //
    case 1:
    default:
        configuredDuration_ = 0; // 
        break;
    }

    elapsedSteps_ = 0;

    qDebug() << "[Backend] setTimeMode:" << mode
             << "duration steps =" << configuredDuration_;
}

void VacuumBackend::setPressureMode(int kpa)
{
    pressureSet_ = kpa;
    qDebug() << "[Backend] setPressureMode:" << kpa << "kPa";
}

void VacuumBackend::start()
{
    elapsedSteps_  = 0;
    lastPressure_  = 0.0f;
    lastPass_      = true;

    qDebug() << "[Backend] start()";
}

void VacuumBackend::step()
{
    if (!isConnected()) {
        qWarning() << "[Backend] step() but not connected";
        return;
    }

    float p = 0.0f;
    if (!measureOnceInternal(1, p)) {
        qWarning() << "[Backend] measureOnceInternal failed";
        return;
    }

    lastPressure_ = p;
    ++elapsedSteps_;

    const float threshold = static_cast<float>(pressureSet_) - 3.0f;
    lastPass_ = (lastPressure_ >= threshold);

    qDebug() << "VAC measure:" << lastPressure_ << "kPa"
             << "elapsed:" << elapsedSteps_
             << "pass:" << (lastPass_ ? "PASS" : "FAIL");
}

void VacuumBackend::refreshPorts()
{
    ports_.clear();
    ports_ = device_.listPorts();
}

int VacuumBackend::portCount() const
{
    return static_cast<int>(ports_.size());
}

const char* VacuumBackend::portName(int index) const
{
    if (index < 0 || index >= static_cast<int>(ports_.size()))
        return nullptr;
    return ports_[static_cast<size_t>(index)].c_str();
}

bool VacuumBackend::connectToPort(const char* portName)
{
    if (!portName) return false;

    QString qPort = QString::fromUtf8(portName);
    qDebug() << "[Backend] connectToPort(" << qPort << ")";

    if (!device_.connectPort(qPort, 19200)) {
        connected_      = false;
        currentPortName_.clear();
        return false;
    }

    connected_       = true;
    currentPortName_ = std::string(portName);

    qDebug() << "[Backend] connectToPort(" << qPort << ") -> true";
    return true;
}

void VacuumBackend::disconnect()
{
    if (connected_) {
        qDebug() << "[Backend] disconnect() from"
                 << QString::fromUtf8(currentPortName_.c_str());
    }

    device_.disconnectPort();
    connected_       = false;
    currentPortName_.clear();
}

bool VacuumBackend::isConnected() const
{
    return connected_ && device_.isConnected();
}

// ───────────────────────────────────────
//  
// ───────────────────────────────────────
bool VacuumBackend::measureOnceInternal(int channel, float& outPressure)
{
    if (!isConnected()) {
        qWarning() << "[Backend] measureOnceInternal: not connected";
        return false;
    }

    return device_.measureOnce(channel, outPressure);
}



bool VacuumBackend::measureAndDecide(int channel, int counter, float& outPressure, float& pSt, float& pSp, float& diffPressure, bool& pass, bool& stop)
{
    if (!isConnected()) {
        qWarning() << "[Backend] measureOnceInternal: not connected";
        return false;
    }
    // qDebug() << "Counter:" <<counter;
    bool result= device_.measureOnce(channel, outPressure);


    if(counter <= STARTOFFSET*DIV )
    {
        pass = true; 
        stop = false; 
        diffPressure = 0.0;
        offsetpress = 0.0;
        startpress = 0.0f;
        stoppress = 0.0f;
        *spcntPtr = 0;
        *stcntPtr = 0;

        if(counter == 1)
        {
            clearAveraging( st_avgpress, sp_avgpress, stcntPtr);
        }

        qDebug() << "Ranger UNDER OFFSET:" <<counter;
        qDebug() << "pressure :" << outPressure;
        qDebug() << "start pressure :" << pSt;
        qDebug() << "stop pressure :" << pSp;
        qDebug() << "diff pressure :" << diffPressure;

    } else if ( counter > STARTOFFSET*DIV && counter <=  (STARTOFFSET*DIV+MAXAVG))
    {
        pass = true; 
        stop = false; 
        diffPressure = 0.0;
        startpress = pSt = averaging(st_avgpress, outPressure,  stcntPtr);
        stoppress = pSp  = averaging(sp_avgpress, outPressure,  spcntPtr);
        if(startpress > 65.0)
        {
            offsetpress = startpress -65.0;
        } else {
            offsetpress = 0.0f;
        }
        startpress = startpress - offsetpress;

        qDebug() << "Ranger BTW OFFSET AND AVG:" <<counter;
        qDebug() << "pressure :" << outPressure;
        qDebug() << "start pressure :" << pSt;
        qDebug() << "stop pressure :" << pSp;
        qDebug() << "diff pressure :" << diffPressure;

    } else if (counter > (STARTOFFSET*DIV+MAXAVG)  && counter <= (configuredDuration_+STARTOFFSET)*DIV+MAXAVG)
    {
        pSp  = averaging(sp_avgpress, outPressure,  spcntPtr);
        pSp = pSp - offsetpress;
        diffPressure = pSp - startpress;
        pSt = startpress;
        //////////////////////////////////////////////////////////////////////
        // pass fail
        if(( pSp >= MINPRESS) && ( diffPressure <= MINDIFF && diffPressure >= -MINDIFF)) {
            pass = true;
            stop = false;
        } else {
            pass = false;
            stop = true;
        }
        qDebug() << "Ranger BTW AVG AND DURATION:" <<counter;
        qDebug() << "pressure :" << outPressure;
        qDebug() << "start pressure :" << pSt;
        qDebug() << "stop pressure :" << pSp;
        qDebug() << "*stcntPtr     :" << *stcntPtr;
        qDebug() << "*spcntPtr     :" << *spcntPtr;
        qDebug() << "diff pressure :" << diffPressure;
    } else {
        pSp  = averaging(sp_avgpress, outPressure,  spcntPtr);
        pSp = pSp - offsetpress;
        diffPressure = pSp - startpress;
        pSt = startpress;
        //////////////////////////////////////////////////////////////////////
        // pass fai
        if(( pSp >= MINPRESS) && ( diffPressure <= MINDIFF && diffPressure >= -MINDIFF)) {
            pass = true;
            stop = true;
        } else {
            pass = false;
            stop = true;
        }
        qDebug() << "Ranger OVER DURATION:" <<counter;
        qDebug() << "pressure :" << outPressure;
        qDebug() << "start pressure :" << pSt;
        qDebug() << "stop pressure :" << pSp;
        qDebug() << "diff pressure :" << diffPressure;
    }
    return result;
    // return device_.measureOnce(channel, outPressure);
}

float VacuumBackend::averaging(float vacarr[], float val,  unsigned int *idx) {
    float total = 0.0;
    if(*idx < MAXAVG) {
        vacarr[(*idx)]= val;
        for( unsigned int i=0; i <= *idx; i++)
        {
            total += vacarr[i];
        }
        (*idx)++;
        return (total/(*idx));
    } else {
        for(unsigned int i=0; i < MAXAVG-1; i++)
        {
            vacarr[i] = vacarr[i+1];
            total += vacarr[i];
        }
        vacarr[MAXAVG-1] = val;
        total += vacarr[MAXAVG-1];
        return (total/MAXAVG);
    }
}


void VacuumBackend::clearAveraging(float vacarr1[], float vacarr2[], unsigned int *idx ) {
    for(unsigned int i=0; i < MAXAVG; i++)
    {
        vacarr1[i] = 0.0;
        vacarr2[i] = 0.0;
    }
    *idx = 0;
}
