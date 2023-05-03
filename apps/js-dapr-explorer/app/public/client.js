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
      $("#result").append("<p><b>POST" + "</b> "+  text  + " <i>" +JSON.stringify(response) + "</i>, " + status + "</p>");
    }).fail(function(xhr, status, message) {
      console.log("message:"+ message);
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
      console.log("message:"+ message);
    });
  });

  $("#head-url").click(function(){
    var text=$("#url").val();

    $.ajax({
      type: "POST",
      url: '/',
      contentType: 'application/json',
      data: JSON.stringify( { "url": text, "action": "HEAD" }),
      dataType: 'json'
    }).done(function(response) {
      $("#result").append("<p><b>HEAD" + "</b> "+  text  + " <i>" +JSON.stringify(response) + "</i>, " + status + "</p>");
    }).fail(function(xhr, status, message) {
      console.log("message:"+ message);
    });
  });

  $("#delete-url").click(function(){
    var text=$("#url").val();

    $.ajax({
      type: "POST",
      url: '/',
      contentType: 'application/json',
      data: JSON.stringify( { "url": text, "action": "DELETE" }),
      dataType: 'json'
    }).done(function(response) {
      $("#result").append("<p><b>DELETE" + "</b> "+  text  + " <i>" +JSON.stringify(response) + "</i>, " + status + "</p>");
    }).fail(function(xhr, status, message) {
        console.log("message:"+ message);
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
      console.log("message:"+ message);
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
      $("#result").append("<p><b>POST" + "</b> "+  text  + " <i>" +JSON.stringify(response) + "</i>, " + status + "</p>");
    }).fail(function(xhr, status, message) {
      console.log("message:"+ message);
    });
  });

  $("#invoke-dapr-head").click(function(){
    var text=$("#url").val();
    $.ajax({
      type: "POST",
      url: '/',
      contentType: 'application/json',
      data: JSON.stringify( { "url": text, "action": "HEAD", "isdaprinvoke": true  }),
      dataType: 'json'
    }).done(function(response) {
      $("#result").append("<p>Dapr<b>HEAD" + "</b> "+  text  + " <i>" +JSON.stringify(response) + "</i>, " + status + "</p>");
    }).fail(function(xhr, status, message) {
      console.log("message:"+ message);
    });
  });

  $("#invoke-dapr-delete").click(function(){
    var text=$("#url").val();
    $.ajax({
      type: "POST",
      url: '/',
      contentType: 'application/json',
      data: JSON.stringify( { "url": text, "action": "DELETE", "isdaprinvoke": true  }),
      dataType: 'json'
    }).done(function(response) {
      $("#result").append("<p>Dapr<b>DELETE" + "</b> "+  text  + " <i>" +JSON.stringify(response) + "</i>, " + status + "</p>");
    }).fail(function(xhr, status, message) {
      console.log("message:"+ message);
    });
  });
});