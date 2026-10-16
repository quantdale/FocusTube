import Foundation

/// Builds the HTML hosting the official IFrame Player (privacy-enhanced
/// youtube-nocookie host, `playsinline=1`). Loaded by the iOS WKWebView engine
/// with `baseURL` = `origin` so the `origin` player var matches.
public enum IFrameEmbedPage {
    public static let messageHandlerName = "focustube"
    public static let defaultOrigin = URL(string: "https://com.quantdale.focustube")!

    public static func playerVars(origin: URL) -> [String: String] {
        [
            "playsinline": "1",
            "enablejsapi": "1",
            "rel": "0",
            "origin": origin.absoluteString,
        ]
    }

    public static func html(origin: URL = defaultOrigin) -> String {
        let vars = playerVars(origin: origin)
            .sorted { $0.key < $1.key }
            .map { "\"\($0.key)\":\"\($0.value)\"" }
            .joined(separator: ",")
        let h = messageHandlerName
        return """
        <!DOCTYPE html><html><head>
        <meta name="viewport" content="width=device-width,initial-scale=1,maximum-scale=1,user-scalable=no">
        <style>html,body{margin:0;padding:0;background:#000;height:100%;overflow:hidden}#player{position:absolute;inset:0;width:100%;height:100%}</style>
        </head><body><div id="player"></div>
        <script src="https://www.youtube.com/iframe_api"></script>
        <script>
        var player;
        function post(e,d){try{window.webkit.messageHandlers.\(h).postMessage({event:e,data:d});}catch(x){}}
        function onYouTubeIframeAPIReady(){
          player=new YT.Player('player',{host:'https://www.youtube-nocookie.com',width:'100%',height:'100%',
            playerVars:{\(vars)},
            events:{
              onReady:function(){post('onReady',null);},
              onStateChange:function(e){post('onStateChange',e.data);},
              onError:function(e){post('onError',e.data);},
              onPlaybackRateChange:function(e){post('onPlaybackRateChange',e.data);}
            }});
          setInterval(function(){if(player&&player.getCurrentTime){post('progress',{currentTime:player.getCurrentTime()||0,duration:player.getDuration()||0});}},500);
        }
        </script></body></html>
        """
    }
}
