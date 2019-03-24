// IOTemp Device Code
// https://github.com/electricimp/thermistor
//#require "Thermistor.class.nut:1.0"
#require "Thermistor.class.nut:1.0"

/* GLOBALS and CONSTANTS -----------------------------------------------------*/

// all calculations are done in Kelvin 
// these are constants for this particular thermistor; if using a different one,
// check your datasheet
const b_therm = 3988;
const t0_therm = 298.15;
const WAKEINTERVAL_MIN = 0.1; // interval between wake-and-reads in minutes
ID <- hardware.getdeviceid(); // Get the deviceID once at the start

/* CLASS AND GLOBAL FUNCTION DEFINITIONS -------------------------------------*/
function setLeds(on, off) {
    foreach(led in on) led.write(1);
    foreach(led in off) led.write(0);
}

function blink() {
    setLeds([redLED, greenLED, yellowLED], []);
    imp.sleep(0.2);
    setLeds([], [redLED, greenLED, yellowLED]);
    imp.sleep(0.2);
    setLeds([redLED, greenLED, yellowLED], []);
    imp.sleep(0.2);
    setLeds([], [redLED, greenLED, yellowLED]);
    imp.sleep(0.2);
    setLeds([redLED, greenLED, yellowLED], []);
    imp.sleep(0.2);
    setLeds([greenLED], [redLED, yellowLED]);
    imp.sleep(0.2);
    setLeds([yellowLED], [redLED, greenLED]);
    imp.sleep(0.2);
    setLeds([redLED], [greenLED, yellowLED]);
    imp.sleep(0.2);
    setLeds([], [redLED, greenLED, yellowLED]);
}

function blinkRed() {
    setLeds([redLED], [greenLED, yellowLED]);
    imp.sleep(0.2);
    setLeds([], [redLED, greenLED, yellowLED]);
    imp.sleep(0.2);
    setLeds([redLED], [greenLED, yellowLED]);
    imp.sleep(0.2);
    setLeds([], [redLED, greenLED, yellowLED]);
    imp.sleep(0.2);
    setLeds([redLED], [greenLED, yellowLED]);
    imp.sleep(0.2);
    setLeds([], [redLED, greenLED, yellowLED]);
    imp.sleep(0.2);
    setLeds([redLED], [greenLED, yellowLED]);
    imp.sleep(0.2);
    setLeds([], [redLED, greenLED, yellowLED]);
}

function lightLED(pData) {
    switch (pData.color) {
        case "GREEN":
            setLeds([greenLED], [redLED, yellowLED]);
            break;
        case "YELLOW":
            setLeds([yellowLED], [redLED, greenLED]);
            break;
        case "RED":
            setLeds([redLED], [yellowLED, greenLED]);
            break;
        case "REDGREEN":
            setLeds([redLED, greenLED], [yellowLED]);
            break;
        case "REDYELLOWGREEN":
            setLeds([redLED, greenLED, yellowLED], []);
            break;
        case "BLINK":
            blink();
            break;
        case "BLINKRED":
            blinkRed();   
            break;
    }
    
//Sleep for the designated amount of time
//if the amount of time is 2 minutes or higher, do a hard sleep because it may be on a battery
  if (pData.sleep_seconds >= 120) {
    // leave the LED lit for 2 seconds
    imp.sleep(2);
    // do a hard sleep for 2 seconds less than requested (because we lit the LED for 2 seconds)
    imp.onidle( function() { 
        server.sleepfor(pData.sleep_seconds - 2); 
    });
// full firmware is reloaded and run from the top on each wake cycle, so no need to construct a loop    
  }
  
  if (pData.sleep_seconds < 120) {
    // send data at time interval based upon JSON response
    imp.wakeup(pData.sleep_seconds, sendData);
  }
}

function sendData() {
    therm_en_l.write(0);
    imp.sleep(0.001);
    

    local datapoint = {
        "id" : ID,
        "temp" : format("%.2f",myThermistor.readF()),
        "impSSID" : imp.getssid() + "_" + imp.getbssid() 
    }
    agent.send("data",datapoint);
    therm_en_l.write(1);
}

// to use a digital to analog converter you need a callback function
function digitalTempReady(buffer, length)
{
    if (length > 0) 
    {
      // We have a valid buffer, so send it to the agent
      
      //agent.send("bufferFull", buffer);
      
      server.log("Received a buffer of length: " + length);
      server.log(buffer);
      
    } 
    else 
    {
      // If length == 0, that's a buffer over-run
      
      server.log("An over-run has taken place");
      hardware.sampler.stop();
    }
}


/* RUNTIME BEGINS HERE -------------------------------------------------------*/
// Configure Pins
therm_en_l <- hardware.pin8;
therm_en_l.configure(DIGITAL_OUT, 1);

// pin 9 is the middle of the voltage divider formed by the NTC - read the analog voltage to determine temperature
temp_sns <- hardware.pin9;

// configure digital thermometer
// Set up the buffers

buffer1 <- blob(2000);
buffer2 <- blob(2000);

// Configure the sampler and register the handler above
hardware.sampler.configure(hardware.pin1, 1000, [buffer1, buffer2], digitalTempReady);

// Start Sampling
hardware.sampler.start();

// Set timer to call stopSampler() in four seconds
// not sure if this is required
//imp.wakeup(4, stopSampler);

// Configure LED pins
redLED    <- hardware.pin7;
redLED.configure(DIGITAL_OUT, 0);
yellowLED <- hardware.pin5;
yellowLED.configure(DIGITAL_OUT, 0);
greenLED  <- hardware.pin2;
greenLED.configure(DIGITAL_OUT, 0);

// instantiate sensor classes

// instantiate our thermistor class
myThermistor <- Thermistor(temp_sns, b_therm, t0_therm, 10, false);

// event listener to light the led
agent.on("led", lightLED)

// start loop
sendData();
