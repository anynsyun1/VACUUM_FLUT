// vacuum_device.h
#pragma once

#include <QtSerialPort/QSerialPort>
#include <QtSerialPort/QSerialPortInfo>
#include <QByteArray>
#include <QString>
#include <vector>


class VacuumDevice
{
public:
    VacuumDevice();
    ~VacuumDevice();

    // 
    bool autoConnect();


    // 
    bool connectPort(const QString& portName, int baud = 19200);

    // 
    void disconnectPort();

    bool isConnected() const { return serial_.isOpen(); }

    // channel: 1=VAC1(PAK), 2=VAC2(CHUCK)
    // 
    bool measureOnce(int channel, float& pressureOut);

    // 
    //  - Windows: "COM4"
    //  - Linux/macOS: "/dev/ttyUSB0", "/dev/ttyS0" 
    std::vector<std::string> listPorts();

private:
    QSerialPort serial_;
    float lastPressure_ = 0.0f;

    QByteArray buildCommand(int channel);
    bool sendCommand(const QByteArray& cmd);
    QByteArray receiveBytes(int timeoutMs);
    float convertRawToPressure(int raw);
};
