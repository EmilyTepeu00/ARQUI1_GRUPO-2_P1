void setup() {
  Serial.begin(9600);
}

void loop() {
  int gas    = analogRead(A0);
  int suelo1 = analogRead(A1);
  int suelo2 = analogRead(A2);
  int luz    = analogRead(A3);

  Serial.print("GAS:");
  Serial.print(gas);
  Serial.print(",SUELO1:");
  Serial.print(suelo1);
  Serial.print(",SUELO2:");
  Serial.print(suelo2);
  Serial.print(",LUZ:");
  Serial.println(luz);

  delay(2000);
}