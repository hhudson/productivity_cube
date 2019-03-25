// Sample code using MMA8452Q accelerometer
// Electric Imp Device Squirrel code
// License:
// This code is provided under the Creative Commons Attribution-ShareAlike 3.0 License
//    http://creativecommons.org/licenses/by-sa/3.0/us/legalcode
// If you find bugs report to duppypro on github or @duppy #MMA8452Q on twitter
// If you find this useful, send a good word to @duppy #MMA8452Q
// Thanks to @jayrz for finding the first bug.

/////////////////////////////////////////////////
// global constants and variables
const versionString = "MMA8452Q Sample v00.01.2013-10-29a"
ID <- hardware.getdeviceid(); 

//const accelChangeThresh = 500 // change in accel per sample to count as movement.  Units of milliGs
pollMMA8452QBusy <- false // guard against interrupt handler collisions FIXME: Is this necessary?  Debugging why I get no EA_BIT set error sometimes
//pollMMA8452QBusy <- true // hhh guard against interrupt handler collisions FIXME: Is this necessary?  Debugging why I get no EA_BIT set error sometimes

///////////////////////////////////////////////
// constants for MMA8452Q i2c registers
// the slave address for this device is set in hardware. Creating a variable to save it here is helpful.
// The SparkFun breakout board defaults to 0x1D, set to 0x1C if SA0 jumper on the bottom of the board is set
const MMA8452Q_ADDR = 0x1D // A '<< 1' is needed.  I add the '<< 1' in the helper functions.
//const MM8452Q_ADDR = 0x1C // Use this address if SA0 jumper is set. 
const STATUS           = 0x00
    const ZYXOW_BIT        = 0x7 // name_BIT == BIT position of name
    const ZYXDR_BIT        = 0x3
const OUT_X_MSB        = 0x01
const SYSMOD           = 0x0B
    const SYSMOD_STANDBY   = 0x00
    const SYSMOD_WAKE      = 0x01
    const SYSMOD_SLEEP     = 0x02
const INT_SOURCE       = 0x0C
    const SRC_ASLP_BIT     = 0x7
    const SRC_FF_MT_BIT    = 0x2
    const SRC_DRDY_BIT     = 0x0
const WHO_AM_I         = 0x0D
    const I_AM_MMA8452Q    = 0x2A // read addr WHO_AM_I, expect I_AM_MMA8452Q
const XYZ_DATA_CFG     = 0x0E
    const FS_2G            = 0x00
    const FS_4G            = 0x01
    const FS_8G            = 0x02
    const HPF_OUT_BIT      = 0x5
const HP_FILTER_CUTOFF = 0x0F
const FF_MT_CFG        = 0x15
    const ELE_BIT          = 0x7
    const OAE_BIT          = 0x6
    const XYZEFE_BIT       = 0x3 // numBits == 3 (one each for XYZ)
        const XYZEFE_ALL       = 0x07 // enable all 3 bits
const FF_MT_SRC        = 0x16
    const EA_BIT           = 0x7
const FF_MT_THS        = 0x17
    const DBCNTM_BIT       = 0x7
    const THS_BIT          = 0x0 // numBits == 7
const FF_MT_COUNT      = 0x18
const ASLP_COUNT       = 0x29
const CTRL_REG1        = 0x2A
    const ASLP_RATE_BIT    = 0x6 // numBits == 2
        const ASLP_RATE_12p5HZ = 0x1
        const ASLP_RATE_1p56HZ = 0x3
    const DR_BIT           = 0x3 // numBits == 3
        const DR_12p5HZ        = 0x5
        const DR_1p56HZ        = 0x7
    const LNOISE_BIT       = 0x2
    const F_READ_BIT       = 0x1
    const ACTIVE_BIT       = 0x0
const CTRL_REG2        = 0x2B
    const ST_BIT           = 0x7
    const RST_BIT          = 0x6
    const SMODS_BIT        = 0x3 // numBits == 2
    const SLPE_BIT         = 0x2
    const MODS_BIT         = 0x0 // numBits == 2
        const MODS_NORMAL      = 0x00
        const MODS_LOW_POWER   = 0x03
const CTRL_REG3        = 0x2C
    const WAKE_FF_MT_BIT   = 0x3
    const IPOL_BIT         = 0x1
const CTRL_REG4        = 0x2D
    const INT_EN_ASLP_BIT  = 0x7
    const INT_EN_LNDPRT_BIT= 0x4
    const INT_EN_FF_MT_BIT = 0x2
    const INT_EN_DRDY_BIT  = 0x0
const CTRL_REG5        = 0x2E

// helper variables for MMA8452Q. These are not const because they may have reason to change dynamically.
i2cRetryPeriod <- 1.0 // seconds to wait before retrying a failed i2c operation //hhh
maxG <- FS_4G // what scale to get G readings
i2c <- hardware.i2c89 // now can use i2c.read()

///////////////////////////////////////////////
//define functions

// start with fairly generic i2c helper functions

function readBitField(val, bitPosition, numBits){ // works for 8bit registers
// bitPosition and numBits are not bounds checked
    return (val >> bitPosition) & (0x00FF >> (8 - numBits))
}

function readBit(val, bitPosition) { return readBitField(val, bitPosition, 1) }

function writeBitField(val, bitPosition, numBits, newVal) { // works for 8bit registers
// newVal is not bounds checked
    //server.log("writeBitField = val: "+writeBitField+"/ bitPosition: "+bitPosition+" / numBits: "+numBits+" / newVal: "+newVal)
    return (val & (((0x00FF >> (8 - numBits)) << bitPosition) ^ 0x00FF)) | (newVal << bitPosition)
}

function writeBit(val, bitPosition, newVal) { return writeBitField(val, bitPosition, 1, newVal) }

// Read a single byte from addressToRead and return it as a byte.  (The '[0]' causes a byte to return)
function readReg(addressToRead) {
    return readSequentialRegs(addressToRead, 1)[0]
}   

// Writes a single byte (dataToWrite) into addressToWrite.  Returns error code from i2c.write
// Continue retry until success.  Caller does not need to check error code
function writeReg(addressToWrite, dataToWrite) {
    //server.log("writeReg = addressToWrite :"+addressToWrite+" / dataToWrite :"+dataToWrite);
    local err = null
    while (err == null) {
        err = i2c.write(MMA8452Q_ADDR << 1, format("%c%c", addressToWrite, dataToWrite))
        // server.log(format("i2c.write addr=0x%02x data=0x%02x", addressToWrite, dataToWrite))
        if (err == null) {
            server.error("i2c.write of value " + format("0x%02x", dataToWrite) + " to " + format("0x%02x", addressToWrite) + " failed.")
            imp.sleep(i2cRetryPeriod)
            server.error("retry i2c.write")
        }
    }
    return err
}

// Read numBytes sequentially, starting at addressToRead
// Continue retry until success.  Caller does not need to check error code
function readSequentialRegs(addressToRead, numBytes) {
    local data = null
    
    while (data == null) {
        data = i2c.read(MMA8452Q_ADDR << 1, format("%c", addressToRead), numBytes)
        if (data == null) {
            server.error("i2c.read from " + format("0x%02x", addressToRead) + " of " + numBytes + " byte" + ((numBytes > 1) ? "s" : "") + " failed.")
            imp.sleep(i2cRetryPeriod)
            server.error("retry i2c.read")
        }
    }
    return data
}

// now functions unique to MMA8452Q

function readAccelData() {
    //server.log("readAccelData");
    local rawData = null // x/y/z accel register data stored here, 3 bytes
    local axisVal = null
    local accelData = array(3)
    local side = null
    local i
    local val
    
    rawData = readSequentialRegs(OUT_X_MSB, 3)  // Read the three raw data registers into data array
    foreach (i, val in rawData) {
        axisVal      = math.floor(1000.0 * ((val < 128 ? val : val - 256) / ((64 >> maxG) + 0.0)))
        accelData[i] = axisVal
            // HACK: in above calc maxG just happens to be (log2(full_scale) - 1)  see: const for FS_2G, FS_4G, FS_8G 
        //convert to signed integer milliGs
    }
    return accelData
}

// Reset the MMA8452Q
function MMA8452QReset() {
    local reg
    
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
    writeReg(CTRL_REG2, writeBit(readReg(CTRL_REG2), RST_BIT, 1))

    do {
        reg = readReg(WHO_AM_I)  // Read WHO_AM_I register
        if (reg == I_AM_MMA8452Q) {
            server.log("MMA8452Q is online!")
            break
        } else {
            server.error("Could not connect to MMA8452Q: WHO_AM_I reg == " + format("0x%02x", reg))
            imp.sleep(i2cRetryPeriod)
        }
    } while (true)
}

function MMA8452QSetActive(mode) {
    server.log("MMA8452Q is set to active.")
    // Sets the MMA8452Q active mode.
    // 0 == STANDBY for changing registers
    // 1 == ACTIVE for outputting data
    writeReg(CTRL_REG1, writeBit(readReg(CTRL_REG1), ACTIVE_BIT, mode))
}

function initMMA8452Q() {
// Initialize the MMA8452Q registers 
// See the many application notes for more info on setting all of these registers:
// http://www.freescale.com/webapp/sps/site/prod_summary.jsp?code=MMA8452Q
    local reg
    
    MMA8452QReset() // Sometimes imp card resets and MMA8452Q keeps power
    // Must be in standby to change registers
    // in STANDBY already after RESET//MMA8452QSetActive(0)

    // Set up the full scale range to 2, 4, or 8g.
    // FIXME: assumes HPF_OUT_BIT in this same register always == 0
    writeReg(XYZ_DATA_CFG, maxG)
    server.log(format("XYZ_DATA_CFG == 0x%02x", readReg(XYZ_DATA_CFG)))
    
    // setup CTRL_REG1
    reg = readReg(CTRL_REG1)
    reg = writeBitField(reg, ASLP_RATE_BIT, 2, ASLP_RATE_1p56HZ)
    reg = writeBitField(reg, DR_BIT, 3, DR_12p5HZ)
    // leave LNOISE_BIT as default off to save power
    // Set Fast read mode to read 8bits per xyz instead of 12bits
    reg = writeBit(reg, F_READ_BIT, 1)
    // set all CTRL_REG1 bit fields in one i2c write
    writeReg(CTRL_REG1, reg)
    server.log(format("CTRL_REG1 == 0x%02x", readReg(CTRL_REG1)))
    
    // setup CTRL_REG2
    reg = readReg(CTRL_REG2)
    // set Oversample mode in sleep
    reg = writeBitField(reg, SMODS_BIT, 2, MODS_LOW_POWER)
    // Enable Auto-SLEEP
    //reg = writeBit(reg, SLPE_BIT, 1)
    // Disable Auto-SLEEP
    reg = writeBit(reg, SLPE_BIT, 0)
    // set Oversample mode in wake
    reg = writeBitField(reg, MODS_BIT, 2, MODS_LOW_POWER)
    // set all CTRL_REG2 bit fields in one i2c write
    writeReg(CTRL_REG2, reg)
    server.log(format("CTRL_REG2 == 0x%02x", readReg(CTRL_REG2)))
    
    // setup CTRL_REG3
    reg = readReg(CTRL_REG3)
    // allow Motion to wake from SLEEP
    reg = writeBit(reg, WAKE_FF_MT_BIT, 1)
    // change Int Polarity
    reg = writeBit(reg, IPOL_BIT, 1)
    // set all CTRL_REG3 bit fields in one i2c write
    writeReg(CTRL_REG3, reg)
    server.log(format("CTRL_REG3 == 0x%02x", readReg(CTRL_REG3)))

    // setup FF_MT_CFG
    reg = readReg(FF_MT_CFG)
    // enable ELE_BIT to latch FF_MT_SRC events
    reg = writeBit(reg, ELE_BIT, 1)
    // enable Motion detection (not Free Fall detection)
    reg = writeBit(reg, OAE_BIT, 1)
    // enable on all axis x, y, and z
    reg = writeBitField(reg, XYZEFE_BIT, 3, XYZEFE_ALL)
    // set all FF_MT_CFG bit fields in one i2c write
    writeReg(FF_MT_CFG, reg)
    server.log(format("FF_MT_CFG == 0x%02x", readReg(FF_MT_CFG)))
    
    // setup Motion threshold to n*0.063.  (16 * 0.063 == 1G)
    writeReg(FF_MT_THS, 60) // FIXME: this is a shortcut and assumes DBCNTM_BIT is 0
    server.log(format("FF_MT_THS == 0x%02x", readReg(FF_MT_THS)))

    // setup sleep counter, the time in multiples of 320ms of no activity to enter sleep mode
    //dont' use ASLP_COUNT for now, use change in prev AccelData reading
    //writeReg(ASLP_COUNT, 10) // 10 * 320ms = 3.2 seconds
    
    //Enable Sleep interrupts
//    writeReg(CTRL_REG4, writeBit(readReg(CTRL_REG4), INT_EN_ASLP_BIT, 1))
    //Enable Motion interrupts
    writeReg(CTRL_REG4, writeBit(readReg(CTRL_REG4), INT_EN_FF_MT_BIT, 1))
    // Enable interrupts on every new data
    writeReg(CTRL_REG4, writeBit(readReg(CTRL_REG4), INT_EN_DRDY_BIT, 1))
    server.log(format("CTRL_REG4 == 0x%02x", readReg(CTRL_REG4)))

    MMA8452QSetActive(1)  // Set to active to start reading
} // initMMA8452Q

// now application specific functions

function pollMMA8452Q() {
    //server.log("pollMMA8452Q invoked.");
    local xyz
    local x
    local y
    local z
    local prevX
    local prevY 
    local prevZ
    local xDiff
    local yDiff
    local zDiff
    local reg
    local prevPrevSide
    local prevSide;
    local side 
// added by anton
    local datapoint    
    local numberSinceChange = 0;
    local changeCounter = 0;

//  end added by anton

    while (pollMMA8452QBusy) {
        //server.log("pollMMA8452QBusy collision")
        //server.log("hello")
        // wait herer unitl other instance of int handler is done
        // FIXME:  I never see this error, probably not neessary, just being paranoid.
    }
    pollMMA8452QBusy = true // mark as busy
    if (hardware.pin1.read() == 1) { // only react to low to high edge
       //server.log("pin1 is 1")
//FIXME:  do we need to check status for data ready in all xyz?//log(format("STATUS == 0x%02x", readReg(STATUS)), 80)
        reg = readReg(INT_SOURCE)
        server.log("reg :"+reg)
        //while (reg != 0x00)//hhh 
        while (1 == 1) {
//            server.log(format("INT_SOURCE == 0x%02x", reg))

            
            
            if (readBit(reg, SRC_DRDY_BIT) == 0x1) {
                xyz = readAccelData() // this clears the SRC_DRDY_BIT
                
                prevSide = side
                //server.log("previsou side: "+ prevSide)
                 
                if (xyz[0] == -1000) {
                    side = 4 //server.log("side 4")
                } else if (xyz[0] > 960) {
                    side = 3 //server.log("side 3")
                } else if (xyz[1] == -1000) {
                    side = 1 //server.log("side 5")
                } else if (xyz[1] > 960) {
                    side = 2 //server.log("side 2")
                } else if (xyz[2] == -1000) {
                    side = 5 //server.log("side 1")
                } else if (xyz[2] > 960) {
                    side = 6 //server.log("side 6")
                } /*else {
                  side = 0
                  //server.log(format("%4d %4d %4d", xyz[0], xyz[1], xyz[2]))
                }*/
                /*x = xyz[0]
                y = xyz[1]
                z = xyz[2]*/
                
                numberSinceChange = numberSinceChange + 1;  // anton
                
                // anton
                if (numberSinceChange == 50) {
                    
                    // send every 100 checks even if it has not changed
                    datapoint = {
                        "id" : ID,
                        "side" : side
                        }
                    agent.send("data",datapoint);
                    
                    changeCounter = changeCounter +1;
                    server.log("changeCounter: " + (changeCounter * 50) );
                    numberSinceChange = 0;
                }
                
                if (side != prevSide) {
                  /*if (prevX == null) {
                      server.log("prevX is null")
                  } else {
                      xDiff = x - prevX
                      server.log("xDiff = "+xDiff)
                  }
                  if (prevX == null) {
                      server.log("prevY is null")
                  } else {
                      yDiff = y - prevY
                      server.log("yDiff = "+yDiff)
                  }
                  if (prevZ == null) {
                      server.log("prevZ is null")
                  } else {
                      zDiff = z - prevZ
                      server.log("zDiff = "+zDiff)
                  }
                  
                  prevX = x
                  prevY = y
                  prevZ = z*/
                  numberSinceChange = 0;
                  changeCounter = 0;
                  
                  server.log("side: "+ side)
// added by Anton
                  server.log("numberSinceChange: " + numberSinceChange);
                  
                  yellowLED.write(1);
                  
                  datapoint = {
                   "id" : ID,
                   "side" : side
                   }
                  agent.send("data",datapoint);
                  
                }
                
                
                // do something with xyz data here
            }
            if (readBit(reg, SRC_FF_MT_BIT) == 0x1) {
                server.log("Interrupt SRC_FF_MT_BIT")
                reg = readReg(FF_MT_SRC) // this clears SRC_FF_MT_BIT
                imp.setpowersave(false) // go to low latency mode because we detected motion
            }
            if (readBit(reg, SRC_ASLP_BIT) == 0x1) {
                reg = readReg(SYSMOD) // this clears SRC_ASLP_BIT
//                server.log(format("Entering SYSMOD 0x%02x", reg))
            }
            reg = readReg(INT_SOURCE)
            imp.sleep(0.25);  // anton
            yellowLED.write(0);
        } // while (reg != 0x00)
    } else {
        server.log("INT2 LOW")
    }
    pollMMA8452QBusy = false; // clear so other inst of int handler can run
    server.log("pollMMA8452Q set to false.");
    
    //greenLED.write(0);
    
    //local timer = imp.wakeup(0.5, pollMMA8452Q(side));  // anton let it sleep a little
} // pollMMA8452Q


function disconnectHandler(reason) {
    if (reason != SERVER_CONNECTED) {
        // Server is not connected, so switch on the 'disconnected' LED...
        redLED.write(0);
        
        server.log("disconnect_reason: " + reason);
        // ... and attempt to reconnect
        // Note that we pass in the same callback we use
        // for unexpected disconnections
        server.connect(disconnectHandler, 5);
        
        server.log("disconnect_reason repeat: " + reason);
        // Set the state flag so that other parts of the
        // application know that the device is offline
        disconnectedFlag = true;
    } else {
        // Server is connected, so turn the 'disconnected' LED off
        // and update the state flag
        redLED.write(1);
        disconnectedFlag = false;
    }
}
    
    
////////////////////////////////////////////////////////
// first code starts here

//imp.setpowersave(true) // start in low power mode.
imp.setpowersave(false) // start in low power mode. hhh doesn't seem to do anything
    // Optimized for case where wakeup was caused by periodic timer, not user activity

// Register with the server
//imp.configure("MMA8452Q 1D6", [], []) // One 6-sided Die
// no in and out []s anymore, using Agent messages

// Send status to know we are alive
//server.log("BOOTING  " + versionString + " " + hardware.getimpid() + "/" + imp.getmacaddress())
server.log("BOOTING  " + versionString + " " + hardware.getdeviceid() + "/" + imp.net.info())
server.log("imp software version : " + imp.getsoftwareversion())

// BUGBUG: below needed until newer firmware!?  See http://forums.electricimp.com/discussion/comment/4875#Comment_2714
// imp.enableblinkup(true)

// added by Anton
//server.setsendtimeoutpolicy(RETURN_ON_ERROR, WAIT_TIL_SENT, 30);

server.onunexpecteddisconnect(disconnectHandler);

local netData = imp.net.info();
if ("active" in netData) {
    local type = netData.interface[netData.active].type;
    
    // We have an active network connection - what type is it?
    if (type == "cell") {
        // The imp is on a cellular connection
        local imei = netData.interface[netData.active].imei;
        server.log("The imp has IMEI " + imei + " and is connected via cellular");
    } else {
        // The imp is connected by WiFi or Ethernet
        local ip = netData.ipv4.address;
        local theSSID = netData.interface[netData.active].ssid;
        server.log("The imp has IP address " + ip + " and is connected via " + type);
        server.log("The imp has SSID " + theSSID);
    }
    
    if (netData.interface.len() > 1) {
        // The imp has more than one possible network interface
        // so note the second (disconnected) one
        local altType = netData.active == 0 ? netData.interface[1].type : netData.interface[0].type;
        server.log("(It can also connect via " + altType + ")");
    }
} else {
    server.log("The imp is not connected");
}

// Configure pin1 for wakeup.  Connect MMA8452Q INT2 pin to imp pin1.
hardware.pin1.configure(DIGITAL_IN_WAKEUP, pollMMA8452Q)

// Configure LED pins
redLED    <- hardware.pin2;
redLED.configure(DIGITAL_OUT, 0);
redLED.write(1);

yellowLED    <- hardware.pin5;
yellowLED.configure(DIGITAL_OUT, 0);
yellowLED.write(0);

greenLED    <- hardware.pin7;
greenLED.configure(DIGITAL_OUT, 0);
greenLED.write(1);

// set the I2C clock speed. We can do 10 kHz, 50 kHz, 100 kHz, or 400 kHz
// i2c.configure(CLOCK_SPEED_400_KHZ)
i2c.configure(CLOCK_SPEED_100_KHZ) // try to fix i2c read errors.  May need 4.7K external pull-up to go to 400_KHZ
initMMA8452Q()  // sets up code to run on interrupts from MMA8452Q

pollMMA8452Q()  // call first time to get a value on boot.

// No more code to execute so we'll sleep until an interrupt from MMA8452Q.
// Sample functions for using MMA8452Q accelerometer
// Electric Imp Device Squirrel (.nut) code
// end of code