when RULE_INIT {
    # Enable this for debug logs!
    # set static::netacea_ingest_debug 0
}

when HTTP_REQUEST {
    if { $static::netacea_ingest_debug } {log local0.debug "HTTP_REQUEST started"}
    set http_request_time [clock clicks -milliseconds]
    if {[catch {ILX::init "Netacea" "netacea"} handle]} {
          log local0.error  "Client - [IP::client_addr], ILX failure: could not reach ILX plugin - make sure it is running in the ILX plugin console"
          # Send user graceful error message, then exit event
          set error 1
          return
        }

    set method [HTTP::method]
    set uri [HTTP::uri]
    set useragent [HTTP::header value "User-Agent"]
    set referer [HTTP::header value "referer"]
    if { $static::netacea_ingest_debug } {log local0.debug "HTTP_REQUEST ended"}
}

when HTTP_RESPONSE {
    if { $static::netacea_ingest_debug } {log local0.debug "HTTP_RESPONSE started"}
    set mitata ""
    set sessionStatus ""

    # calcluate request time
    set http_response_time [clock clicks -milliseconds]
    set request_time [ expr {$http_response_time - $http_request_time} ]
    if {[catch {ILX::call $handle ingest [IP::client_addr] $useragent [HTTP::status] $method $uri "http" $referer [HTTP::header value "Content-Length"] $request_time $mitata $sessionStatus} result]} {
       log local0.error  "Client - [IP::client_addr], ILX failure: could not reach ingest API"
       # Send user graceful error message, then exit event
       return
    }
    if { $static::netacea_ingest_debug } {log local0.debug "HTTP_RESPONSE ended"}
}



