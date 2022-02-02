$(document).ready(function(){
  $("#post-url").click(function(){
    var text=$("#url").val();
    
    $.ajax({
      type: "POST",
      url: '/',
      contentType: 'application/json',
      data: JSON.stringify( { "url": text, "action": "POST" }),
      dataType: 'json'
    }).done(function(response) {
      $("#result").append("<p><b>GET" + "</b> "+  text  + " <i>" +JSON.stringify(response) + "</i>, " + status + "</p>");
    }).fail(function(xhr, status, message) {
        console.log("message");
    });
    
  });

  $("#get-url").click(function(){
    var text=$("#url").val();

    $.ajax({
      type: "POST",
      url: '/',
      contentType: 'application/json',
      data: JSON.stringify( { "url": text, "action": "GET" }),
      dataType: 'json'
    }).done(function(response) {
      $("#result").append("<p><b>GET" + "</b> "+  text  + " <i>" +JSON.stringify(response) + "</i>, " + status + "</p>");
    }).fail(function(xhr, status, message) {
        console.log("message");
    });
  });

  $("#invoke-dapr-get").click(function(){
    var text=$("#url").val();

    $.ajax({
      type: "POST",
      url: '/',
      contentType: 'application/json',
      data: JSON.stringify( { "url": text, "action": "GET", "isdaprinvoke": true  }),
      dataType: 'json'
    }).done(function(response) {
      $("#result").append("<p><b>GET" + "</b> "+  text  + " <i>" +JSON.stringify(response) + "</i>, " + status + "</p>");
    }).fail(function(xhr, status, message) {
        console.log("message");
    });
  });

  $("#invoke-dapr-post").click(function(){
    var text=$("#url").val();
    $.ajax({
      type: "POST",
      url: '/',
      contentType: 'application/json',
      data: JSON.stringify( { "url": text, "action": "POST", "isdaprinvoke": true  }),
      dataType: 'json'
    }).done(function(response) {
      $("#result").append("<p><b>GET" + "</b> "+  text  + " <i>" +JSON.stringify(response) + "</i>, " + status + "</p>");
    }).fail(function(xhr, status, message) {
        console.log("message");
    });
  });
});