// vacuum_device.cpp
// vacuum_device.cpp

#include "vacuum_device.h"
#include <QDebug>

VacuumDevice::VacuumDevice()
{
}

VacuumDevice::~VacuumDevice()
{
    disconnectPort();
}

std::vector<std::string> VacuumDevice::listPorts()
{
    std::vector<std::string> result;

    const auto infos = QSerialPortInfo::availablePorts();
    for (const QSerialPortInfo& info : infos) {
#ifdef Q_OS_WIN
        // Windows: "COM4"
        result.push_back(info.portName().toStdString());
#else
        // Linux/macOS: "/dev/ttyUSB0" 같은 풀패스
        result.push_back(info.systemLocation().toStdString());
#endif
    }

    return result;
}

bool VacuumDevice::autoConnect()
{
    if (serial_.isOpen())
        return true;

    const auto infos = QSerialPortInfo::availablePorts();
    for (const QSerialPortInfo& info : infos) {
        const QString name = info.portName();
        if (name.contains("USB", Qt::CaseInsensitive) ||
            name.contains("COM", Qt::CaseInsensitive)) {
            qDebug() << "[VacuumDevice] autoConnect try:" << name;
            if (connectPort(name, 19200)) {
                qDebug() << "[VacuumDevice] autoConnect success:" << name;
                return true;
            }
        }
    }

    qWarning() << "[VacuumDevice] autoConnect failed: no port";
    return false;
}

bool VacuumDevice::connectPort(const QString& portName, int baud)
{
    if (serial_.isOpen())
        serial_.close();

    serial_.setPortName(portName);
    serial_.setBaudRate(baud);
    serial_.setDataBits(QSerialPort::Data8);
    serial_.setParity(QSerialPort::NoParity);
    serial_.setStopBits(QSerialPort::OneStop);
    serial_.setFlowControl(QSerialPort::NoFlowControl);

    if (!serial_.open(QIODevice::ReadWrite)) {
        qWarning() << "[VacuumDevice] Failed to open"
                   << portName << ":" << serial_.errorString();
        return false;
    }

    qDebug() << "[VacuumDevice] CONNECTED:" << portName;
    return true;
}

void VacuumDevice::disconnectPort()
{
    if (serial_.isOpen()) {
        qDebug() << "[VacuumDevice] disconnectPort()";
        serial_.close();
    }
}

QByteArray VacuumDevice::buildCommand(int channel)
{
    QByteArray cmd;
    cmd.resize(5);

    if (channel == 1) {         // VAC1
        cmd[0] = 'V';
        cmd[1] = 'A';
        cmd[2] = 'C';
        cmd[3] = '1';
    } else if (channel == 2) {  // VAC2
        cmd[0] = 'V';
        cmd[1] = 'A';
        cmd[2] = 'C';
        cmd[3] = '2';
    } else {                    // STOP (참고용)
        cmd[0] = 'S';
        cmd[1] = 'T';
        cmd[2] = 'P';
        cmd[3] = '3';
    }

    cmd[4] = 0x00;  // null-like tail
    return cmd;
}

bool VacuumDevice::sendCommand(const QByteArray& cmd)
{
    if (!serial_.isOpen()) {
        qWarning() << "[VacuumDevice] sendCommand: device not open";
        return false;
    }

    const qint64 written = serial_.write(cmd);
    if (written != cmd.size()) {
        qWarning() << "[VacuumDevice] write failed, written:" << written;
        return false;
    }

    if (!serial_.waitForBytesWritten(100)) {
        qWarning() << "[VacuumDevice] waitForBytesWritten timeout";
        return false;
    }

    qDebug() << "[VacuumDevice] Sending command:" << cmd;
    return true;
}

QByteArray VacuumDevice::receiveBytes(int timeoutMs)
{
    QByteArray data;

    if (!serial_.isOpen())
        return data;

    if (!serial_.waitForReadyRead(timeoutMs))
        return data;

    data = serial_.readAll();
    while (serial_.waitForReadyRead(20)) {
        data += serial_.readAll();
    }

    qDebug() << "[VacuumDevice] received bytes:" << data.toHex(' ');
    return data;
}


/*
float VacuumDevice::convertRawToPressure(quint8 raw)
{
    float pressure = 0.0f;
    float slop = 0.0f;
    float bias = 0.0f;

    if (raw >= 88) { // over 60(3C), 50Kpa
        slop  = (88.0f - 255.0f) / (65.0f - 50.0f);
        bias  = 255.0f;
        pressure = (static_cast<float>(raw) - bias) / slop;
    } else if (raw < 88 && raw >= 48) {
        slop  = (48.0f - 88.0f) / (80.0f - 65.0f);
        bias  = 261.333f;
        pressure = (static_cast<float>(raw) - bias) / slop;
    } else {
        slop  = (0.0f - 48.0f) / (100.0f - 80.0f);
        bias  = 240.0f;
        pressure = (static_cast<float>(raw) - bias) / slop;
    }

    if (pressure >= 100.0f)
        pressure = 100.0f;

    return pressure;
}
*/

float VacuumDevice::convertRawToPressure(int adcValue)
{
    int outRange = 0;
    // 0~255 범위 보정
    int adc = qBound(0, adcValue, 255);

    // (ADC, kPa) 보정 테이블
    const QVector<QPair<int, double>> cal = {
        {  0, 100.0 },   // 100 kPa
        { 48,  80.0 },   // 80 kPa
        //{ 88,  65.0 },   // 65 kPa
        // { 81,  65.0 },   // 65 kPa
        //{ 81,  69.0 },   // 65 kPa // VAC
        //{ 95,  65.0 },   // 65 kPa // CHUCK
        { 95,  65.0 },   // 65 kPa // CHUCK
        {125,  50.0 },   // 50 kPa
        {255,   0.0 }    // 0 kPa
    };

    // 구간 클램프
    if (adc <= cal.first().first) {
        if (outRange) outRange = 2;
        return cal.first().second;
    }

    if (adc >= cal.last().first) {
        if (outRange) outRange = 0;
        return cal.last().second;
    }

    // 선형 보간
    for (int i = 0; i < cal.size() - 1; ++i)
    {
        int x0 = cal[i].first;
        int x1 = cal[i + 1].first;
        double y0 = cal[i].second;
        double y1 = cal[i + 1].second;

        if (adc >= x0 && adc <= x1)
        {
            // 기존 if/else 구간 정의 유지
            if (outRange) {
                if (adc >= 88)      outRange = 0; // 65~0 kPa
                else if (adc >= 48) outRange = 1; // 80~65 kPa
                else                outRange = 2; // 100~80 kPa
            }

            double t = double(adc - x0) / double(x1 - x0);
            return y0 + t * (y1 - y0);
        }
    }

    return qQNaN(); // 안전장치
}



bool VacuumDevice::measureOnce(int channel, float& pressureOut)
{
    if (!serial_.isOpen()) {
        qWarning() << "[VacuumDevice] measureOnce: device not open";
        return false;
    }

    const QByteArray cmd = buildCommand(channel);
    if (!sendCommand(cmd))
        return false;

    const QByteArray rx = receiveBytes(200);
    if (rx.isEmpty()) {
        qWarning() << "[VacuumDevice] measureOnce: no response";
        return false;
    }

    const quint8 raw = static_cast<quint8>(rx[0]);
    const float p    = convertRawToPressure(raw);

    lastPressure_ = p;
    pressureOut   = p;

    qDebug() << "[VacuumDevice] measureOnce result:" << p << "kPa";
    return true;
}
