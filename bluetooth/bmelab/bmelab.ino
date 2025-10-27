#include <SoftwareSerial.h>

SoftwareSerial BTSerial(2, 3); // RX (connect to TXD), TX (connect to RXD)
bool start_recv = false;
const long baud_rate = 9600;
int in = A0;
bool adc_running = false;
unsigned long last_send_time = 0;
const unsigned long send_interval = 100; // 發送間隔 (毫秒)

void setup() {
Serial.begin(baud_rate);
BTSerial.begin(baud_rate);
Serial.println("Arduino 藍牙發送器已啟動");
Serial.println("等待藍牙連接...");
}

void loop() {
// 檢查藍牙接收
if (BTSerial.available()) {
String received = BTSerial.readString();
received.trim();
Serial.print("Received: ");
Serial.println(received);
// 處理接收到的指令
if (received == "START_ADC") {
adc_running = true;
Serial.println("開始ADC數據傳輸");
BTSerial.println("ADC_TRANSMISSION:STARTED");
}
else if (received == "STOP_ADC") {
adc_running = false;
Serial.println("停止ADC數據傳輸");
BTSerial.println("ADC_TRANSMISSION:STOPPED");
}
else if (received == "STATUS") {
Serial.println("狀態查詢");
BTSerial.println("SYSTEM_STATUS:READY");
}
else if (received == "HELLO") {
Serial.println("通訊測試");
BTSerial.println("HEARTBEAT:OK");
}
}
// 如果ADC正在運行，定期發送數據
if (adc_running && (millis() - last_send_time >= send_interval)) {
int adc_value = analogRead(A0);
double voltage = (adc_value * 5.0) / 1023.0;
// 發送格式化的數據
String data_string = "ADC_DATA:" + String(adc_value) + "," + String(voltage, 3);
BTSerial.println(data_string);
// 在序列埠監視器中也顯示
Serial.print("ADC: ");
Serial.print(adc_value);
Serial.print(" (");
Serial.print(voltage, 3);
Serial.println("V)");
last_send_time = millis();
}
}