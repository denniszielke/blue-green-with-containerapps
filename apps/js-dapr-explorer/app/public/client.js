$(document).ready(function(){
  $("#post-url").click(function(){
    var text=$("#url").val();
    $.post("/", { url: text, action: "POST" }, function(data, status){
       $("#result").append("<p><b>POST" + "</b> "+  text  + " <i>" +JSON.stringify(data) + "</i>, " + status + "</p>");
    });
  });

  $("#get-url").click(function(){
    var text=$("#url").val();
    $.post("/", { url: text, action: "GET" }, function(data, status){
       $("#result").append("<p><b>GET" + "</b> " + text +  " <i>" +JSON.stringify(data) + "</i>, " + status + "</p>");
    });
  });

  $("#invoke-dapr-get").click(function(){
    var text=$("#url").val();
    $.post("/", { url: text, action: "GET", isdaprinvoke: true }, function(data, status){
      $("#result").append("<p><b>Dapr GET" + "</b> " + text + " <i>" +JSON.stringify(data) + "</i>, " + status + "</p>");
    });
  });

  $("#invoke-dapr-post").click(function(){
    var text=$("#url").val();
    $.post("/", { url: text, action: "POST", isdaprinvoke: true }, function(data, status){
      $("#result").append("<p><b>Dapr POST" + "</b> " + text + " <i>" +JSON.stringify(data) + "</i>, "+ status + "</p>");
    });
  });
});