require('dotenv-extended').load();
const config = require('./config');
const appInsights = require("applicationinsights");
if (config.instrumentationKey){ 
    appInsights.setup(config.instrumentationKey)
    .setAutoDependencyCorrelation(true)
    .setAutoCollectDependencies(true)
    .setAutoCollectPerformance(true)
    .setSendLiveMetrics(true)
    .setDistributedTracingMode(appInsights.DistributedTracingModes.AI_AND_W3C);
    appInsights.defaultClient.context.tags[appInsights.defaultClient.context.keys.cloudRole] = "calc-frontend";
    appInsights.start();
    const client = appInsights.defaultClient;
    client.commonProperties = {
        slot: config.version
    };
}

const express = require('express');
const app = express();
const morgan = require('morgan');
const OS = require('os');
const axios = require('axios');

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

app.post('/api/calculation', async (req, res, next) => {
    console.log("received frontend request:");
    console.log(req.headers);
    let victim = false;
    const targetNumber = req.headers.number.toString();
    const randomvictim = Math.floor((Math.random() * 20) + 1);
    if (config.buggy && randomvictim){
        victim = true;
    }

    if (config.cacheEndPoint){
        console.log("calling caches:");
        axios({
            method: 'get',
            url: config.cacheEndPoint + '/' + targetNumber,
            headers: {    
                'dapr-app-id': 'js-calc-frontend'
            }})
            .then(function (response) {
                console.log("received cache response:");
                console.log(response.data);
                const cacheBody = response.data;
                if (cacheBody != null && cacheBody.toString().length > 0 )
                {   
                    console.log("cache hit");
                    console.log(cacheBody);
                    res.send({ host: OS.hostname(), version: config.version, 
                        backend: { host: "cache",  value: "[" + cacheBody + "]", remote: "cache" } });

                } else
                {
                    console.log("cache miss");
                    
                    axios({
                        method: 'post',
                        url: config.endpoint + '/api/calculation',
                        headers: {    
                            'number': targetNumber,
                            'randomvictim': victim,
                            'dapr-app-id': 'js-calc-frontend'
                        }})
                        .then(function (response) {
                            console.log("received backend response:");
                            console.log(response.data);
                            const appResponse = {
                                host: OS.hostname(), version: config.version, 
                                backend: { host: response.data.host, version: response.data.version, value: response.data.value, remote: response.data.remote, timestamp: response.data.timestamp } 
                            };
                            res.send(appResponse);
                            console.log("updating cache:");
                            const cacheData = '[{"key":"' + targetNumber + '","value":"'+ response.data.value.toString() + '"}]';
                            console.log(cacheData);
                            axios({
                                method: 'post',
                                url: config.cacheEndPoint,
                                headers: {    
                                    'Content-Type': 'application/json',
                                    'dapr-app-id': 'js-calc-frontend'
                                },
                                data: cacheData
                            }).then(function (response) {
                                console.log("updated cache");
                                console.log(response.data);
                            }).catch(function (error) {
                                console.log("failed to update cache:");
                                console.log(error.response.data);
                            });
        
                        }).catch(function (error) {
                            console.log("error:");
                            console.log(error);
                            const backend = { 
                                host: error.response.data.host || "frontend", 
                                version: error.response.data.version || "red", 
                                value: error.response.data.value || [ 'b', 'u', 'g'], 
                                timestamp: error.response.data.timestamp || ""
                            };
                            res.send({ backend: backend, error: "looks like a cache failure" + error.response.status + " from " + error.response.statusText, host: OS.hostname(), version: config.version });
                        });
                }
                            
                }).catch(function (error) {
                    console.log("error:");
                    console.log(error.response);
                    console.log("data:");
                    console.log(error.response.data);
                    const backend = { 
                        host: error.response.data.host || "frontend", 
                        version: error.response.data.version || "red", 
                        value: error.response.data.value || [ 'b', 'u', 'g'], 
                        timestamp: error.response.data.timestamp || ""
                    };
                    res.send({ backend: backend, error: "looks like " + error.response.status + " from " + error.response.statusText, host: OS.hostname(), version: config.version });
                });         

    }
    else{

        axios({
            method: 'post',
            url: config.endpoint + '/api/calculation',
            headers: {    
                'number': req.headers.number,
                'randomvictim': victim,
                'dapr-app-id': 'js-calc-frontend'
            }})
            .then(function (response) {
                console.log("received backend response:");
                console.log(response.data);
                const appResponse = {
                    host: OS.hostname(), version: config.version, 
                    backend: { host: response.data.host, version: response.data.version, value: response.data.value, remote: response.data.remote, timestamp: response.data.timestamp } 
                };
                res.send(appResponse);
            }).catch(function (error) {
                console.log("error:");
                console.log(error.response);
                console.log("data:");
                console.log(error.response.data);
                const backend = { 
                    host: error.response.data.host || "frontend", 
                    version: error.response.data.version || "red", 
                    value: error.response.data.value || [ 'b', 'u', 'g'], 
                    timestamp: error.response.data.timestamp || ""
                };
                res.send({ backend: backend, error: "looks like " + error.response.status + " from " + error.response.statusText, host: OS.hostname(), version: config.version });
            });
    }
    
});

app.post('/api/dummy', function(req, res) {
    console.log("received dummy request:");
    console.log(req.headers);
    res.send({ value: "[ 42 ]", host: OS.hostname(), version: config.version });
});

console.log(config);
console.log(OS.hostname());
app.listen(config.port);
console.log('Listening on localhost:'+ config.port);