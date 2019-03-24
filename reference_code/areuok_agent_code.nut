// Are you ok? widget for monitoring loved ones

// license: Beerware.
// It is ok to use, reuse, and modify this code for personal or commercial projects. 
// If you do, consider adding a note in the comments giving a reference to 
// this project and/or buying me a beer some day. 

// This agent monitors the device, making sure it communicates
// and gets moved by its user regularly. This will also send messages
// via twitter (email and Twilio texting is an exercise
// left to the next person).

/************************ Settings  ***************************************/

// debug output frequency: these prevent twitter flurries where you
// get the same message 10 times because you are tapping the device
const dtDebugMessageMotionDetected = 80; // seconds
const dtDebugMessageBatteryUpdateDetected = 600; // seconds

// This is how long the device will go without an update from the
// user before it cries for help
//      43200   ==> 12 hours ==> three times a day
//      129600  ==> 36 hours ==> every day (not same time every day)
//      216000  ==> 60 hours ==> every couple days
const dtNoMotionDetected = 129600; // seconds 
const dtNoBatteryUpdate = 21600; // seconds (21600 ==> 6 hours)
const dtEverythingFineUpdate = 432000; // seconds (432000 ==> 5 days)

const MIN_GOOD_STATE_OF_CHARGE = 25; // percent

// Twitter permissions for @ayok_status
// It is ok to use this as long as you update the monitoredDevices
// so it prints your mane. 
// Also note, it is for debug: if abused, the permissions will 
// change (and remember others can see these tweets!).
_CONSUMER_KEY <- "HxwLkDWJTHDZo5z3nENPA"
_CONSUMER_SECRET <- "HvlmFx9dkp7j4odOIdfyD9Oc7C5RyJpI7HhEzHed4G8"
_ACCESS_TOKEN <- "2416179944-INBz613eTjbzJN4q4iymufCcEsP5XJ6xW5Lr8Kp"
_ACCESS_SECRET <- "1YdwAiJViQY45oP8tljdX0PGPyeL8G3tQHKtO43neBYqH"

// Twilio set up for texting 
// http://forums.electricimp.com/discussion/comment/4736
// more extensive code https://github.com/joel-wehr/electric_imp_security_system/blob/master/agent.nut

// Mailgun for emailing
// http://captain-slow.dk/2014/01/07/using-mailgun-with-electric-imp/

/************************ Handle setting the device's name ***************************************/
// You have to set up your unit the first time by putting in a URL:
// https://agent.electricimp.com/{agentUrl}/settings?name={nameValue}&attn={attnValue}
// Look at the top of the Imp editor for you agent URL, you'll see something like
//    https://agent.electricimp.com/abce1235  <-- random string numbers and letters
// So you'll build up one that looks like
// https://agent.electricimp.com/abce1235/settings?name={Maxwell}&attn={@logicalelegance}
// Where Maxwell is the name of the unit and @logicalelegance is where I want messages to be sent.

// default settings
settings <- { 
    name = "Unknown",   // name of the unit
    attn = ""           // who to send messages to
};

// Loads settings, if they exist
function loadSettings() {
    // load data
    local data = server.load();

    // if there are settings
    if ("settings" in data) {
        settings.name = data.settings.name;
        settings.attn = data.settings.attn;
    }
} 

// Load settings on agent start/restart
loadSettings();

// Saves the settings with server.save
function saveSettings(newName, newAttn) {
    // load settings
    local data = server.load();

    // if settings isn't in the stored data
    if (!("settings" in data)) {
        // create settings table in data
        data["settings"] <- { name = "", attn = "" };
    }

    // set new values
    settings.name = newName;
    settings.attn = newAttn;

    // save values
    data.settings.name = newName;
    data.settings.attn = newAttn;
    server.save(data);
}


function httpHandler(req, resp) {
    // grab the path the request was made to
    local path = req.path.tolower();
    // if they made a request to /settings:
    if (path == "/settings" || path == "/settings/") {
        // grab query parameters we need
        if ("name" in req.query && "attn" in req.query) {
            // save them
            saveSettings(req.query.name, req.query.attn);
            // respond with the new settings
            resp.send(200, http.jsonencode(settings));
            return;
        }
    }
    // if they didn't send settings pass back a 200, OK
    resp.send(200, "OK");
}

// attach httpHandler to onrequest event
http.onrequest(httpHandler);


/************************ Twitter ***************************************/
// from: github.com/electricimp/reference/tree/master/webservices/twitter
helper <- {
    function encode(str) {
        return http.urlencode({ s = str }).slice(2);
    }
}

class TwitterClient {
    consumerKey = null;
    consumerSecret = null;
    accessToken = null;
    accessSecret = null;

    baseUrl = "https://api.twitter.com/";

    constructor (_consumerKey, _consumerSecret, _accessToken, _accessSecret) {
        this.consumerKey = _consumerKey;
        this.consumerSecret = _consumerSecret;
        this.accessToken = _accessToken;
        this.accessSecret = _accessSecret;
    }

    function post_oauth1(postUrl, headers, post) {
        local time = time();
        local nonce = time;

        local parm_string = http.urlencode({ oauth_consumer_key = consumerKey });
        parm_string += "&" + http.urlencode({ oauth_nonce = nonce });
        parm_string += "&" + http.urlencode({ oauth_signature_method = "HMAC-SHA1" });
        parm_string += "&" + http.urlencode({ oauth_timestamp = time });
        parm_string += "&" + http.urlencode({ oauth_token = accessToken });
        parm_string += "&" + http.urlencode({ oauth_version = "1.0" });
        parm_string += "&" + http.urlencode({ status = post });

        local signature_string = "POST&" + helper.encode(postUrl) + "&" + helper.encode(parm_string)

        local key = format("%s&%s", helper.encode(consumerSecret), helper.encode(accessSecret));
        local sha1 = helper.encode(http.base64encode(http.hash.hmacsha1(signature_string, key)));

        local auth_header = "oauth_consumer_key=\""+consumerKey+"\", ";
        auth_header += "oauth_nonce=\""+nonce+"\", ";
        auth_header += "oauth_signature=\""+sha1+"\", ";
        auth_header += "oauth_signature_method=\""+"HMAC-SHA1"+"\", ";
        auth_header += "oauth_timestamp=\""+time+"\", ";
        auth_header += "oauth_token=\""+accessToken+"\", ";
        auth_header += "oauth_version=\"1.0\"";

        local headers = { 
            "Authorization": "OAuth " + auth_header,
        };

        local response = http.post(postUrl + "?status=" + helper.encode(post), headers, "").sendsync();
        return response
    }

    function Tweet(_status) {
        local postUrl = baseUrl + "1.1/statuses/update.json";
        local headers = { };

        local response = post_oauth1(postUrl, headers, _status)
        if (response && response.statuscode != 200) {
            twitterDebug("Error updating_status tweet. HTTP Status Code " + response.statuscode);
            twitterDebug(response.body);
            return null;
        } else {
           twitterDebug("Tweet Successful!");
        }
    }
}

function twitterDebug(string)
{
    // when debugging twitter, turn on the server logging
    // server.log(string)
}

twitter <- TwitterClient(_CONSUMER_KEY, _CONSUMER_SECRET, _ACCESS_TOKEN, _ACCESS_SECRET);
/**************************** End twitter block  *******************************************/


/**************************** Message block  *******************************************/
// Returns a preformated DateTime string.
// Helper function for debugMessage
function GetDateTimeStr(timestamp) {
    local d = date(timestamp, 'u'); // UTC time
    local day = ["Sun", "Mon", "Tues", "Wed", "Thurs", "Fri", "Sat"];

    return format("%s %02d:%02d:%02d", day[d.wday], d.hour,  d.min, d.sec)
}

// These are the messages you use when bringing up the device,
// for checking that the battery is draining slowly and 
// testing taps. These don't use the attn string so on
// Twitter they are relatively quiet
function debugMessage(string)
{
    local message = settings.name + ": " + string;    

    twitter.Tweet(message);
    server.log(message)
}


// These are the important messages:
// 1) No user motion
// 2) Batteries are low
// 3) Intermittent, everything is fine
function caregiverMessage(string)
{
    local message = settings.name + ": " + string;

    twitter.Tweet(attn + " " message);
    server.log("!!!!" + message);
}


/**************************** Device handling  *******************************************/
local lastTimeMotionDetected = 0;
local lastTimeBatteryUpdate = 0;
local lastBatteryReading = 0;
local batteryUpdateFromDeviceTimer;
local motionUpdateFromDeviceTimer;
local everythingIsFineDeviceTimer;

// This creates a debug string if motion is sent from the device
// More importantly, it resets the timer so we don't send an "I'm lonely" message
function motionOnDevice(type)
{
    local thisCheckInTime = time();
    if ((lastTimeMotionDetected != 0) && 
        ((thisCheckInTime - lastTimeMotionDetected) > dtDebugMessageMotionDetected)) {

        local datestr = GetDateTimeString(thisCheckInTime);
        local sendStr = datestr + " I felt movement. It was a " + type;
        debugMessage(sendStr);
    }
    lastTimeMotionDetected = thisCheckInTime;
    imp.cancelwakeup(motionUpdateFromDeviceTimer);
    motionUpdateFromDeviceTimer = imp.wakeup(dtNoMotionDetected, noMotionFromDevice);

}

function noMotionFromDevice()
{
    local stringOptions = [
        "No one has played with me since ",
        "I need to be pet but haven't been since ",
        "The last time someone filled my cuddle tank was ",
        "It's been eons since my last hug: ",
        "I'm so lonely, no one has paid attention to me for so long: ",
        "I'm hungry, hungry for hugs! Last feeding was "
        ];

    if (lastTimeMotionDetected) {

        local datestr = GetDateTimeString(lastTimeMotionDetected);
        local choice  = math.rand() % stringOptions.len();
        local sendStr = stringOptions[choice] + datestr;
        caregiverMessage(sendStr)
    } else {
        sendStr = "No movement since device turned on!"
        caregiverMessage(sendStr)
    }
    motionUpdateFromDeviceTimer = imp.wakeup(dtNoMotionDetected, noMotionFromDevice);

    eveverythingNotFine();
}

function noBatteryUpdateFromDevice()
{
    local sendStr;
    if (lastTimeBatteryUpdate) {
        local stringOptions = [
            "Device did not check in, last check in at ",
            ];

        local datestr = GetDateTimeStr(lastTimeBatterUpdate);
        local choice  = math.rand() % stringOptions.len();
        sendStr = stringOptions[choice] + datestr + 
              " battery then: " + lastBatteryReading + 
            ", minutes " + (time() - lastTimeBatteryUpdate)/60;
    } else { 
        sendStr = "Device has not checked in since server restart."
    }
    caregiverMessage(sendStr)

    batteryUpdateFromDeviceTimer = imp.wakeup(dtNoBatteryUpdate, noBatteryUpdateFromDevice);
    eveverythingNotFine();
}
function eveverythingNotFine()
{
    // everything is not fine, reset counter to happy message
    imp.cancelwakeup(everythingIsFineDeviceTimer);
    everythingIsFineDeviceTimer = imp.wakeup(dtEverythingFineUpdate, everythingFineUpdate);
}

function everythingFineUpdate()
{
    local sendStr;
    if (lastBatteryReading > MIN_GOOD_STATE_OF_CHARGE) {
        local stringOptions = [
            "Nothing to be concerned about, everything is going really well! Battery at %d %%",
            ];

        local choice  = math.rand() % stringOptions.len();
        sendStr = stringOptions[choice];
    } else {
        local stringOptions = [
            "Things are going fine but my batteries are getting low: %d %%",
            ];

        local choice  = math.rand() % stringOptions.len();
        sendStr = stringOptions[choice];
    }

    caregiverMessage(format(sendStr, lastBatteryReading));

    everythingIsFineDeviceTimer = imp.wakeup(dtEverythingFineUpdate, everythingFineUpdate);
}

function batteryUpdateFromDevice(percentFull)
{
    local thisCheckInTime = time();
    if ((thisCheckInTime - lastTimeBatteryUpdate) > dtDebugMessageBatteryUpdateDetected) {
        local datestr = GetDateTimeStr(thisCheckInTime);
        local sendStr = datestr + " battery update: " + percentFull ;
        debugMessage(sendStr)
    }    
    // update the device timer
    imp.cancelwakeup(batteryUpdateFromDeviceTimer);
    batteryUpdateFromDeviceTimer = imp.wakeup(dtNoBatteryUpdate, noBatteryUpdateFromDevice);
    lastTimeBatteryUpdate = thisCheckInTime;
    lastBatteryReading = percentFull;
} 

// register the device actions. It will wake up with the accelerometer says
// to (motion). It will also wake up on a timer to read the battery.
device.on("motionDetected", motionOnDevice);
device.on("batteryUpdate", batteryUpdateFromDevice);

// This timer is to complain if we haven't heard anything from the device.
// We should be getting ~ hourly battery updates. If we miss more than one 
// or two, then the device is having trouble with communication (or its
// batteries are dead). We need to fuss because the regular monitoring is
// therefore also offline.
batteryUpdateFromDeviceTimer = imp.wakeup(dtNoBatteryUpdate, noBatteryUpdateFromDevice);

// This is the critical timer, if the device does not sense motion in this 
// time it will fuss
motionUpdateFromDeviceTimer = imp.wakeup(dtNoMotionDetected, noMotionFromDevice);

// Everyone needs to know things are ok. So every few days, we'll send an
// all clear to indicate everything is functioning normally.
everythingIsFineDeviceTimer = imp.wakeup(dtEverythingFineUpdate, everythingFineUpdate);
