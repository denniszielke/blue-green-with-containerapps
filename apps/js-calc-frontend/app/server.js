require('dotenv-extended').load();
const config = require('./config');
var appInsights = require("applicationinsights");
if (config.instrumentationKey){ 
    appInsights.setup(config.instrumentationKey)
    .setAutoDependencyCorrelation(true)
    .setAutoCollectDependencies(true)
    .setAutoCollectPerformance(true)
    .setSendLiveMetrics(true)
    .setDistributedTracingMode(appInsights.DistributedTracingModes.AI_AND_W3C);
    appInsights.defaultClient.context.tags[appInsights.defaultClient.context.keys.cloudRole] = "calc-frontend";
    appInsights.start();
    var client = appInsights.defaultClient;
    client.commonProperties = {
        slot: config.version
    };
}
const express = require('express');
const app = express();
const morgan = require('morgan');
const request = require('request');
const OS = require('os');
require('isomorphic-fetch');

var publicDir = require('path').join(__dirname, '/public');

// add logging middleware
app.use(morgan('dev'));
app.use(express.static(publicDir));

// Routes
app.get('/ping', function(req, res) {
    console.log('received ping');
    var sourceIp = req.connection.remoteAddress;
    var forwardedFrom = (req.headers['x-forwarded-for'] || '').split(',').pop();
    var pong = { response: "pong!", host: OS.hostname(), source: sourceIp, forwarded: forwardedFrom, version: config.version };
    console.log(pong);
    res.send(pong);
});

app.get('/healthz', function(req, res) {
    res.send('OK');
});

app.get('/api/getappinsightskey', function(req, res) {
    console.log('returned app insights key');
    if (config.instrumentationKey){ 
        res.send(config.instrumentationKey);
    }
    else{
        res.send('');
    }
});

app.post('/api/calculation', function(req, res) {
    console.log("received frontend request:");
    console.log(req.headers);
    var victim = false;
    var targetNumber = req.headers.number.toString();
    var randomvictim = Math.floor((Math.random() * 20) + 1);
    if (config.buggy && randomvictim){
        victim = true;
    }

    if (config.cacheEndPoint){
       
        var cacheGetOptions = { 
            'url': config.cacheEndPoint + '/' + targetNumber,
            'headers': {
                'dapr-app-id': 'js-calc-frontend'
            }
        };    
        console.log("calling caches:");
        console.log(cacheGetOptions);
        request.get(cacheGetOptions, function(cacheErr, cacheRes, cacheBody) {

            if (cacheErr){
                console.log("error:");
                console.log(cacheErr);
                res.send({ value: "[ b, u, g]", error: "looks like a local cache issue", host: OS.hostname(), version: config.version });
            } else {
                console.log("cache result:");
                
                if (cacheBody != null && cacheBody.toString().length > 0 )
                {   
                    console.log("cache hit");
                    console.log(cacheBody);
                    res.send({ host: OS.hostname(), version: config.version, 
                        backend: { host: "cache",  value: "[" + cacheBody + "]", remote: "cache" } });

                } else
                {
                    console.log("cache miss");
                    var formData = {
                        received: new Date().toLocaleString(), 
                        number: targetNumber
                    };
                    var options = { 
                        'url': config.endpoint + '/api/calculation',
                        'form': formData,
                        'headers': {
                            'number': targetNumber,
                            'randomvictim': victim,
                            'dapr-app-id': 'js-calc-frontend'
                        }
                    };    
                    request.post(options, function(innererr, innerres, body) {
                        if (innererr){
                            console.log("calcu error:");
                            console.log(innererr);
                            res.send({ value: "[ b, u, g]", error: "looks like a local failure bug", host: OS.hostname(), version: config.version });
                        }
                        else {
                            console.log("calculation result:");
                            console.log(body);
                            var calcResult = JSON.parse(body); 

                            var response = { host: OS.hostname(), version: config.version, 
                                backend: { host: calcResult.host, version: calcResult.version, value: calcResult.value, remote: calcResult.remote, timestamp: calcResult.timestamp } };
                            console.log(response);

                            var cacheData = '[{"key":"' + targetNumber + '","value":"'+ calcResult.value.toString() + '"}]';
                            // cacheData ='[{ "key": "key1", "value": "value1"}]';
                            var cacheSetOptions = { 
                                'url': config.cacheEndPoint,
                                'headers': {
                                    'dapr-app-id': 'js-calc-frontend',
                                    'Content-Type': 'application/json'
                                },
                                'data': cacheData
                            };  
                            console.log(cacheSetOptions);
                            
                            fetch(config.cacheEndPoint, {
                                method: "POST",
                                body: cacheData,
                                headers: {
                                    "Content-Type": "application/json"
                                }
                            }).then((response) => {
                                if (!response.ok) {
                                    throw "Failed to persist state.";
                                }
                        
                                console.log("Successfully persisted state.");
                                res.status(200).send();
                            }).catch((error) => {
                                console.log(error);
                                res.status(500).send({message: error});
                            });

                            console.log(response);
                            res.send(response);
                        }
                    });   
                } 
            }
        });   
    }else{
        var formData = {
            received: new Date().toLocaleString(), 
            number: req.headers.number
        };
        var options = { 
            'url': config.endpoint + '/api/calculation',
            'form': formData,
            'headers': {
                'number': req.headers.number,
                'randomvictim': victim
            }
        };    
        request.post(options, function(innererr, innerres, body) {
            if (innererr){
                console.log("error:");
                console.log(innererr);
            }
                        
            var calcResult = JSON.parse(body); 

            var response = { host: OS.hostname(), version: config.version, 
                backend: { host: calcResult.host, version: calcResult.version, value: calcResult.value, remote: calcResult.remote, timestamp: calcResult.timestamp } };

            console.log(response);
            res.send(response);
        });
    }
    
});

app.post('/api/dummy', function(req, res) {
    console.log("received dummy request:");
    console.log(req.headers);
    res.send('42');
});

console.log(config);
console.log(OS.hostname());
app.listen(config.port);
console.log('Listening on localhost:'+ config.port);