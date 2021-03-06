package com.axis.rtspclient {

  import flash.events.EventDispatcher;
  import flash.events.ErrorEvent;
  import flash.events.Event;
  import flash.events.IOErrorEvent;
  import flash.events.ProgressEvent;
  import flash.events.SecurityErrorEvent;
  import flash.net.Socket;
  import flash.utils.ByteArray;
  import mx.utils.Base64Encoder;

  import com.axis.rtspclient.GUID;
  import com.axis.http.url;
  import com.axis.http.auth;
  import com.axis.http.request;

  public class RTSPoverHTTPHandle extends EventDispatcher implements IRTSPHandle {

    private var getChannel:Socket = null;
    private var postChannel:Socket = null;
    private var urlParsed:Object = {};
    private var sessioncookie:String = "";

    private var base64encoder:Base64Encoder;

    private var datacb:Function = null;
    private var connectcb:Function = null;

    private var authState:String = "none";
    private var authOpts:Object = {};
    private var digestNC:uint = 1;

    private var getChannelData:ByteArray;
    private var postChannelData:ByteArray;

    public function RTSPoverHTTPHandle(urlParsed:Object) {
      this.sessioncookie = GUID.create();
      this.urlParsed = urlParsed;
      this.base64encoder = new Base64Encoder();
    }

    private function setupSockets():void
    {
      getChannel = new Socket();
      getChannel.timeout = 5000;
      getChannel.addEventListener(Event.CONNECT, onGetChannelConnect);
      getChannel.addEventListener(ProgressEvent.SOCKET_DATA, onGetChannelData);
      getChannel.addEventListener(IOErrorEvent.IO_ERROR, onError);
      getChannel.addEventListener(SecurityErrorEvent.SECURITY_ERROR, onError);

      postChannel = new Socket();
      postChannel.timeout = 5000;
      postChannel.addEventListener(Event.CONNECT, onPostChannelConnect);
      postChannel.addEventListener(IOErrorEvent.IO_ERROR, onError);
      postChannel.addEventListener(SecurityErrorEvent.SECURITY_ERROR, onError);

      getChannelData = new ByteArray();
      postChannelData = new ByteArray();
    }

    private function base64encode(str:String):String {
      base64encoder.reset();
      base64encoder.insertNewLines = false;
      base64encoder.encode(str);
      return base64encoder.toString();
    }

    public function writeUTFBytes(value:String):void
    {
      postChannel.writeUTFBytes(base64encode(value));
      postChannel.flush();
    }

    public function readBytes(bytes:ByteArray, offset:uint = 0, length:uint = 0):void
    {
      getChannel.readBytes(bytes, offset, length);
    }

    private function onError(e:ErrorEvent):void {
      trace("HTTPClient socket error");
    }

    public function disconnect():void {
      if (getChannel.connected) {
        getChannel.close();
      }
      if (postChannel.connected) {
        postChannel.close();
      }

      /* should probably wait for close, but it doesn't seem to fire properly */
      dispatchEvent(new Event('closed'));
    }

    public function connect():void {
      setupSockets();
      getChannel.connect(this.urlParsed.host, this.urlParsed.port);
    }

    public function reconnect():void
    {
      throw new Error('RTSPoverHTTPHandle: reconnect not implemented');
    }

    private function onGetChannelConnect(event:Event):void {
      initializeGetChannel();
    }

    private function onPostChannelConnect(event:Event):void {
      initializePostChannel();
    }

    public function stop():void {
      disconnect();
    }

    private function onGetChannelData(event:ProgressEvent):void {
      var parsed:* = request.readHeaders(getChannel, getChannelData);
      if (false === parsed) {
        return;
      }

      if (401 === parsed.code) {
        trace('Unauthorized using auth method: ' + authState);
        /* Unauthorized, change authState and (possibly) try again */
        authOpts = parsed.headers['www-authenticate'];
        var newAuthState:String = auth.nextMethod(authState, authOpts);
        if (authState === newAuthState) {
          trace('GET: Exhausted all authentication methods.');
          trace('GET: Unable to authorize to ' + urlParsed.host);
          return;
        }

        trace('switching http-authorization from ' + authState + ' to ' + newAuthState);
        authState = newAuthState;
        getChannelData = new ByteArray();
        getChannel.close();
        getChannel.connect(this.urlParsed.host, this.urlParsed.port);
        return;
      }

      if (200 !== parsed.code) {
        trace('Invalid HTTP code: ' + parsed.code);
        return;
      }

      getChannel.removeEventListener(ProgressEvent.SOCKET_DATA, onGetChannelData);
      getChannel.addEventListener(ProgressEvent.SOCKET_DATA, function(ev:ProgressEvent):void {
        dispatchEvent(new Event('data'));
      });
      postChannel.connect(this.urlParsed.host, this.urlParsed.port);
    }

    private function initializeGetChannel():void {
      getChannel.writeUTFBytes("GET " + urlParsed.urlpath + " HTTP/1.0\r\n");
      getChannel.writeUTFBytes("X-Sessioncookie: " +  sessioncookie + "\r\n");
      getChannel.writeUTFBytes("Accept: application/x-rtsp-tunnelled\r\n");
      getChannel.writeUTFBytes(auth.authorizationHeader("GET", authState, authOpts, urlParsed, digestNC++));
      getChannel.writeUTFBytes("\r\n");
      getChannel.flush();
    }

    private function initializePostChannel():void {
      postChannel.writeUTFBytes("POST " + urlParsed.urlpath + " HTTP/1.0\r\n");
      postChannel.writeUTFBytes("X-Sessioncookie: " + sessioncookie + "\r\n");
      postChannel.writeUTFBytes("Content-Length: 32767" + "\r\n");
      postChannel.writeUTFBytes("Content-Type: application/x-rtsp-tunnelled" + "\r\n");
      postChannel.writeUTFBytes(auth.authorizationHeader("POST", authState, authOpts, urlParsed, digestNC++));
      postChannel.writeUTFBytes("\r\n");
      postChannel.flush();

      dispatchEvent(new Event('connected'));
    }
  }
}
