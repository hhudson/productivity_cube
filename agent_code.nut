// IOTemp Agent Code

/* 
   Change Log
   2014-12-31 ANielsen 1.00.00 Build 17 Created Agent Code
   2015-1-01  NNielsen 1.00.01 Build 19 Changed name of post function to "postToC2App"
   2015-01-06 ANielsen 1.00.02 Build 21 Added postToC2IOT
*/

/* GLOBALS and CONSTANTS -----------------------------------------------------*/

const ORDS_URL = "https://apex.oracle.com/pls/apex/%s/iotemp/temp/";


/* CLASS AND GLOBAL FUNCTION DEFINITIONS -------------------------------------*/

function postToC2LED(data,id,impSSID) {
    
    // call Anton's service to get the schema mapping for this imp_id
    local aUrl = format("https://apex.oracle.com/pls/apex/anton/impUtils/schema/%s/%s/%s", id, data, impSSID);
    local aHeaders = { "User-Agent" : "C2-Imp-Lib/0.1" };
    local aResponse = http.get(aUrl, aHeaders).sendsync();
    
    if(aResponse.statuscode != 200) {
		    server.log("error with step1 http request, status: " + aResponse.statuscode);
		    server.log("url: " + aUrl);
			server.log("error with step1 http request: " + aResponse.body);

		    local sleepTime = 20;
		    local blinkColor = "BLINKRED";
		    local JSONString = {"sleep_seconds": sleepTime, "color": blinkColor };

		    server.log("JSONString.color: " + JSONString.color);
		    device.send("led", JSONString);			
			return null;
	}
	
    // convert the json response and log the schema name
    local aJSONData = http.jsondecode(aResponse.body);
    //server.log("header: "+aResponse.headers);
    server.log("schema: "+ aJSONData.schema);
	
	if(aJSONData.schema == "xxinvalidxx") {
	    server.log("error getting schema, status: " + aResponse.statuscode);
		server.log("body: " + aResponse.body);
		
		local sleepTime = 20;
		local blinkColor = "REDYELLOWGREEN";
		local JSONString = {"sleep_seconds": sleepTime, "color": blinkColor };

		server.log("JSONString.color: " + JSONString.color);
		device.send("led", JSONString);
		return null;
	}    
    
    // insert the schema retrieved above into the request url
	local url = format(ORDS_URL, aJSONData.schema);
	//local headers = { "User-Agent" : "C2-Imp-Lib/0.1" };
	
	local headers = { "Content-Type": "application/json" };
	
	local requestData = { "impid": id, "temp": data };
	local body = http.jsonencode(requestData);
	
	server.log(url);
	server.log(body);

	local response = http.post(url, headers, body).sendsync();
	
	if(response.statuscode != 201) {
	    server.log("error with http request, status: " + response.statuscode);
		server.log("error with http request: " + response.body);

	    local sleepTime = 20;
	    local blinkColor = "BLINK";
	    local JSONString = {"sleep_seconds": sleepTime, "color": blinkColor };

	    server.log("JSONString.color: " + JSONString.color);
	    device.send("led", JSONString);			
		return null;
	}

    local JSONdata = http.jsondecode(response.body);
    
    server.log("Posted to C2 LED: "+data+", got return code: "+response.statuscode+", msg: "+response.body+" JSONdata.color: "+JSONdata.color+" JSONdata.sleep_seconds: "+JSONdata.sleep_seconds) ;
    //device.send("led", response.body);
    device.send("led", JSONdata);
}



/* REGISTER DEVICE CALLBACKS  ------------------------------------------------*/

device.on("data", function(datapoint) {
    postToC2LED(datapoint.temp, datapoint.id, datapoint.impSSID);
});

/* REGISTER HTTP HANDLER -----------------------------------------------------*/

// This agent does not need an HTTP handler

/* RUNTIME BEGINS HERE -------------------------------------------------------*/

server.log("TempBug Agent Running");
