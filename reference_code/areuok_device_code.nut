// Are you ok? widget for monitoring loved ones

// It is ok to use, reuse, and modify this code for personal or commercial projects. 
// License: Beerware.
// If you do, consider adding a note in the comments giving a reference to 
// this project and/or buying me a beer some day. 

/**************************** User parameters ***************************************/
// Imp's hardware.voltage reads the output of the regulator so we don't see the 
// whole range of the batteries, do the best with the info available
const MAX_EXPECTED_VOLTAGE = 3.3; // max readable
const MIN_EXPECTED_VOLTAGE = 2.6; // dying
const MIN_GOOD_STATE_OF_CHARGE = 25; // percent


// when there is movement, how much movement does there have to be
// to get the accelerometer to wake up the device
const ACCEL_TAP_THRESHOLD = 10; // experimentally derived threshold
const ACCEL_TRANSIENT_THRESHOLD = 0x02;  // experimentally derived threshold

// the LED ramps up to a color, holds for a bit, then ramps down
const LED_HOLD_TIME = 5.0; // seconds
const LED_RAMP_STEP_TIME = 0.05; // seconds per ramp step (0.05 = 200Mhz)
const LED_RAMP_STEPS = 20; // steps in ramp at timing above


/**************************** Hardware *******************************************/
 /* Pin Assignments according to silkscreen
 * Pin 1 = Input: wakeup interrupt from accelerometer
 * Pin 2 = PWM Red
 * Pin 5 = PWM Blue
 * Pin 7 = PWM Green
 * Pin 8 = I2C SCL  (yellow wire for me)
 * Pin 9 = I2C SDA  (green wire for me)
*/

wakeupPin <- hardware.pin1;
redHWPin <- hardware.pin2;
greenHWPin <- hardware.pin5;
blueHWPin <- hardware.pin7;
i2c <- hardware.i2c89; 
i2c.configure(CLOCK_SPEED_400_KHZ);
/**************************** LED *******************************************/
// Variable to represent LED state
class LEDColor
{
    redPin = null
    greenPin = null
    bluePin = null

    goalLED = [0xFF, 0xFF, 0xFF]; // power on goal is white
    currentLED = [0, 0, 0]; 
    inLEDRamp = false; // prevents multiple LED flares

    constructor(redPin, greenPin, bluePin) {
        // PWM frequency in Hz
        local pwm_f = 500.0;
        redPin.configure(PWM_OUT, 1.0/pwm_f, 0.0);
        greenPin.configure(PWM_OUT, 1.0/pwm_f, 0.0);
        bluePin.configure(PWM_OUT, 1.0/pwm_f, 0.0);

        this.redPin = redPin
        this.greenPin = greenPin
        this.bluePin = bluePin
        this.off();
    }

    function update() {
        local div =  (1.0/255.0);
        this.redPin.write( currentLED[0] * div);
        this.greenPin.write( currentLED[1] * div);
        this.bluePin.write( currentLED[2] * div);
    }        
    function off() {
        this.redPin.write(0);
        this.greenPin.write(0);
        this.bluePin.write(0);
    }

    function setGoalColor (red, green, blue)
    {
        if (inLEDRamp) {
            // not updating if we are already doing something
        } else {
            goalLED[0] = red;
            goalLED[1] = green;
            goalLED[2] = blue;

            ledRamp();
            inLEDRamp = true;
        }
    }
}
local rgbLed = LEDColor(redHWPin, greenHWPin, blueHWPin);

// this function looks at the difference between the goal LED
// and the actual LED and finds a way to smoothly transition
function ledRamp() 
{
    local difference = [0, 0, 0];
    local totalDifference = 0;
    local i;
    for (i = 0; i < 3; i++) {
        difference[i] = rgbLed.goalLED[i] - rgbLed.currentLED[i];   
        if (0 < difference[i] && difference[i] < LED_RAMP_STEPS) {
            difference[i] = LED_RAMP_STEPS; // will be 1 after divide

        } else if (0 > difference[i] && -difference[i] < LED_RAMP_STEPS) {
            difference[i] = -LED_RAMP_STEPS; // will be -1
        }
        rgbLed.currentLED[i] += (difference[i] / LED_RAMP_STEPS);
        totalDifference += difference[i];
    }
    if (-3 < totalDifference && totalDifference < 3) {
        local goal = 0;
        for (i = 0; i < 3; i++) {
            goal += rgbLed.goalLED[i];
            rgbLed.currentLED[i] = rgbLed.goalLED[i]; 
            rgbLed.goalLED[i] = 0;
        }
        if (goal == 0) {
            // finished
            rgbLed.inLEDRamp = false;
            rgbLed.off();
            GetReadyToSleep();

        } else {
            rgbLed.update();
            imp.wakeup(LED_HOLD_TIME, ledRamp);  // it will start ramping down
        }
    } else { 
        rgbLed.update();
        imp.wakeup(LED_RAMP_STEP_TIME, ledRamp);
    }
}

/************************ Battery monitoring ***************************************/
// This project originally used a rechargeable battery with a MAX17043 LiPo fuel 
// gauge to determine the state of charge (SOC). However, since the Impee is sleeping 
// so much, we might get a reasonable battery life out of 4AAs. To get back to 
// rechargeable, replace this code with that found in rechargeable_device.

function FuelGaugeResetFromBoot()
{
    // do nothing
}

function FuelGaugeReadSoC()
{
    local voltage = hardware.voltage();
    local normalizedVoltgage = (voltage - MIN_EXPECTED_VOLTAGE) / (MAX_EXPECTED_VOLTAGE - MIN_EXPECTED_VOLTAGE);
    if (normalizedVoltgage < 0) normalizedVoltgage = 0
    local percent = math.floor(100 * normalizedVoltgage);

    return percent;
}

/************************ Accelerometer ***************************************/
// Many thanks to https://gist.github.com/duppypro/7225636 
// I mooched much of that code for the MMA8452Q accelerometer, though I made some
// changes for efficiency

const ACCEL_ADDR = 0x3A // 0x1D << 1
// Note: if your accelerometer has the SAO line pulled down 
// (the resistor on the Sparkfun board), change the address to 
/// const ACCEL_ADDR = 0x38 // 0x1C << 1

// MMA8452 register addresses and bitmasks
const STATUS        = 0x00
const OUT_X_MSB        = 0x01
const WHO_AM_I         = 0x0D
const I_AM_MMA8452Q    = 0x2A // read addr WHO_AM_I, expect I_AM_MMA8452Q
const INT_SOURCE       = 0x0C
    const SRC_ASLP_BIT        = 0x80
    const SRC_TRANSIENT_BIT   = 0x20
    const SRC_ORIENTATION_BIT = 0x10
    const SRC_PULSE_BIT       = 0x08
    const SRC_FF_MT_BIT       = 0x04
    const SRC_DRDY_BIT        = 0x01

const TRANSIENT_CFG = 0x1D
const TRANSIENT_SRC = 0x1E
const TRANSIENT_THRESHOLD = 0x1F
const TRANSIENT_COUNT = 0x20

const PULSE_CFG = 0x21
const PULSE_SRC = 0x22
const PULSE_THSX = 0x23
const PULSE_THSY = 0x24
const PULSE_THSZ = 0x25
const PULSE_TMLT = 0x26
const PULSE_LTCY = 0x27
const PULSE_WIND = 0x28


const CTRL_REG1         = 0x2A
    const GOAL_DATA_RATE = 0x20 // 100 Hz
    const CLEAR_DATA_RATE =0xC7
    const LNOISE_BIT       = 0x4
    const F_READ_BIT       = 0x2
    const ACTIVE_BIT       = 0x1    

const CTRL_REG2        = 0x2B
    const ST_BIT           = 0x7
    const RST_BIT          = 0x6
    const SLEEP_OVERSAMPLE_CLEAR = 0xE7 
    const SLEEP_OVERSAMPLE_SET = 0x18 // 11 = low power
    const AUTOSLEEP_BIT         = 0x4
    const NORMAL_OVERSAMPLE_CLEAR = 0xFC 
    const NORMAL_OVERSAMPLE_SET = 0x03 // 11 = low power

const CTRL_REG3        = 0x2C
    const WAKE_TRANSIENT_BIT     = 0x40
    const WAKE_ORIENTATION_BIT   = 0x20
    const WAKE_PULSE_BIT         = 0x10
    const WAKE_FREEFALL_BIT      = 0x08
    const IPOL_BIT               = 0x02

const CTRL_REG4        = 0x2D
    const INT_EN_ASLP_BIT        = 0x80
    const INT_EN_TRANSIENT_BIT   = 0x20
    const INT_EN_ORIENTATION_BIT = 0x10
    const INT_EN_PULSE_BIT       = 0x08
    const INT_EN_FREEFALL_MT_BIT = 0x04
    const INT_EN_DRDY_BIT        = 0x01

const CTRL_REG5        = 0x2E


// Writes a single byte (dataToWrite) into addressToWrite.  Returns error code from i2c.write
// Continue retry until success.  Caller does not need to check error code
function writeReg(addressToWrite, dataToWrite) {
    local err = null
    while (err == null) {
        err = i2c.write(ACCEL_ADDR, format("%c%c", addressToWrite, dataToWrite))
        // server.log(format("i2c.write addr=0x%02x data=0x%02x", addressToWrite, dataToWrite))
        if (err == null) {
            server.error("i2c.write of value " + format("0x%02x", dataToWrite) + " to " + format("0x%02x", addressToWrite) + " failed.")
        }
    }
    return err

}

// Read numBytes sequentially, starting at addressToRead
// Continue retry until success.  Caller does not need to check error code
function readSequentialRegs(addressToRead, numBytes) {
    local data = null

    while (data == null) {
        data = i2c.read(ACCEL_ADDR, format("%c", addressToRead), numBytes)
        if (data == null) {
            server.error("i2c.read from " + format("0x%02x", addressToRead) + " of " + numBytes + " byte" + ((numBytes > 1) ? "s" : "") + " failed.")
        }
    }
    return data
}

function readReg(addressToRead) {
    return readSequentialRegs(addressToRead, 1)[0]
}  
function AccelerometerSetActive(mode) {
    // Sets the MMA8452Q active mode. 
    // 0 == STANDBY for changing registers
    // 1 == ACTIVE for outputting data
    if (mode) {
        writeReg(CTRL_REG1, readReg(CTRL_REG1) | ACTIVE_BIT)
    } else {
        writeReg(CTRL_REG1, readReg(CTRL_REG1) & ~ACTIVE_BIT)
    }
}
// Reset the accelerometer
function AccelerometerResetFromBoot() {
    local reg = null;

    server.log("Looking for accelerometer...")
    do {
        reg = readReg(WHO_AM_I)  // Read WHO_AM_I register
        if (reg == I_AM_MMA8452Q) {
            server.log("Found MMA8452Q.  Sending RST command...")
            break
        } else {
            server.error("Could not connect to MMA8452Q: WHO_AM_I reg == " + format("0x%02x", reg))
            imp.sleep(i2cRetryPeriod)
        }
    } while (true)

    // send reset command
    writeReg(CTRL_REG2, readReg(CTRL_REG2) | RST_BIT)

    do {
        reg = readReg(WHO_AM_I)  // Read WHO_AM_I register
        if (reg == I_AM_MMA8452Q) {
            server.log("Accelerometer found.")
            break
        } else {
            server.error("Could not connect to MMA8452Q: WHO_AM_I reg == " + format("0x%02x", reg))
            imp.sleep(i2cRetryPeriod)
        }
    } while (true)

    AccelerometerSetActive(false);
    writeReg(CTRL_REG1, 0x1A); // 100 Hz ODR + fast read + low noise

    // Set up accel for transient detection, see 
    // http://cache.freescale.com/files/sensors/doc/app_note/AN4071.pdf
    writeReg(TRANSIENT_CFG, 0x1E); // Enable X Y Z Axes and enable the latch
    writeReg(TRANSIENT_THRESHOLD, ACCEL_TRANSIENT_THRESHOLD);
    writeReg(TRANSIENT_COUNT, 0x05); // 50ms
    reg = readReg(TRANSIENT_SRC) // this clears the register

    // Set up accel for single tap pulse detection, see 
    // http://cache.freescale.com/files/sensors/doc/app_note/AN4072.pdf
    writeReg(PULSE_CFG, 0x55); // Enable X Y Z Axes and enable the latch
    writeReg(PULSE_THSX, ACCEL_TAP_THRESHOLD); 
    writeReg(PULSE_THSY, ACCEL_TAP_THRESHOLD); 
    writeReg(PULSE_THSZ, ACCEL_TAP_THRESHOLD); 
    writeReg(PULSE_TMLT, 0x03); // 30ms at 100Hz ODR
    writeReg(PULSE_LTCY, 100);  // 100ms at 100Hz ODR
    reg = readReg(PULSE_SRC) // this clears the register

    writeReg(CTRL_REG4, INT_EN_TRANSIENT_BIT | INT_EN_PULSE_BIT); 
    writeReg(CTRL_REG5, INT_EN_TRANSIENT_BIT | INT_EN_PULSE_BIT);  

    writeReg(CTRL_REG3, WAKE_TRANSIENT_BIT | WAKE_PULSE_BIT | IPOL_BIT);  // move to int1

    AccelerometerSetActive(true);
}
function readAccelData() {
    local rawData = null // x/y/z accel register data stored here, 3 bytes
    rawData = readSequentialRegs(OUT_X_MSB, 3)  // Read the three raw data registers into data array
    return rawData;
}

function AccelerometerIRQ() {
    local reg = null


    if (wakeupPin.read() == 1) { // only react to low to high edge
        IndicateGoodInteraction();
        reg = readReg(INT_SOURCE)
        if (reg & SRC_TRANSIENT_BIT) {
            reg = readReg(TRANSIENT_SRC) // this clears SRC_TRANSIENT_BIT
            server.log(format("Transient src 0x%02x", reg))
            agent.send("motionDetected", "soft gentle motion.");
        }


        if (reg & SRC_PULSE_BIT) {
            reg = readReg(PULSE_SRC) // this clears SRC_PULSE_BIT
            server.log(format("Pulse src 0x%02x", reg))
            agent.send("motionDetected", "hard rapping.");
        }

    } else {
//        server.log("INT LOW")
    }
} // end AccelerometerIRQ

/************************ Device code  ***************************************/
function GetReadyToSleep()
{
    local sleepSeconds = 3600; // an hour
    // this will effectively reset the system when it comes back on
    server.sleepfor(sleepSeconds);
}

function CheckBatteryAndGoToSleep()
{
    agent.send("batteryUpdate", FuelGaugeReadSoC());
    server.log("going  to sleep");
    imp.onidle(GetReadyToSleep);
}

function IndicateGoodInteraction()
{
    rgbLed.setGoalColor(255, 255, 255); // white
}
function IndicateLowBattery()
{
    rgbLed.setGoalColor(200, 200, 0); // yellow
}
function IndicateNoWiFi()
{
    rgbLed.setGoalColor(255, 0, 0); // red
}

function HandleReasonForWakeup(unused = null) 
{
    local reason = hardware.wakereason();
    local stateOfCharge = FuelGaugeReadSoC();
    local timeout = 30;


    if (reason == WAKEREASON_TIMER) {
        // quiet wakeup
        server.log("Timer wakeup")
        CheckBatteryAndGoToSleep(); 
    } else {
        if  (!server.isconnected()) {
            IndicateNoWiFi()
        } 
        if (stateOfCharge < MIN_GOOD_STATE_OF_CHARGE)
        {
            server.log("Low battery " + stateOfCharge)
            IndicateLowBattery();
        }

        if (reason == WAKEREASON_PIN1) {
            server.log("PIN1 wakeup")
            AccelerometerIRQ();
        } else { // any other reason is a reset of sorts
            server.log("Reboot")
            AccelerometerResetFromBoot();
            FuelGaugeResetFromBoot();
        }
    }
}

// things to do on every time based wake up
imp.setpowersave(true);

// on error: don't try to reconnect, throw an error so we can indicate a 
// problem to the user
server.setsendtimeoutpolicy(RETURN_ON_ERROR, WAIT_TIL_SENT, 30);

// Configure interrupt for wakeup.  Connect MMA8452Q INT1 pin to imp pin1.
wakeupPin.configure(DIGITAL_IN_WAKEUP, AccelerometerIRQ);

// figure out why we woke up
if  (!server.isconnected()) {
    // we probably can't get to the internet, try for 
    // a little while (3 seconds), then get pushed to 
    // HandleReasonForWakeup where IndicateNoWiFi will be called
    server.connect(HandleReasonForWakeup, 3)
} else {
    HandleReasonForWakeup();
}
