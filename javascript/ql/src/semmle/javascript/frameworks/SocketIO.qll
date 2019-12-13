/**
 * Provides classes for working with [socket.io](https://socket.io).
 */

import javascript
private import semmle.javascript.dataflow.InferredTypes

/**
 * Provides classes for working with server-side socket.io code
 * (npm package `socket.io`).
 *
 * We model three concepts: servers, namespaces, and sockets. A server
 * has one or more namespaces associated with it, each identified by
 * a path name. There is always a default namespace associated with the
 * path "/". Data flows between client and server side through sockets,
 * with each socket belonging to a namespace on a server.
 */
// TODO: Restore SocketNode, NamespaceNode, ServerNode. And revert the Namespace class.
// Go through all the previous classes, and ensure they exist.
// Have all the .ref() methods return *Node objects.
module SocketIO {
  abstract private class SocketIOObject extends DataFlow::SourceNode,
    EventEmitter::EventEmitterRange::Range { }

  /** A socket.io server. */
  class ServerObject extends SocketIOObject {
    ServerObject() {
      this = DataFlow::moduleImport("socket.io").getAnInvocation()
      or
      // alias for `Server`
      this = DataFlow::moduleImport("socket.io").getAMemberCall("listen")
    }

    /** Gets the default namespace of this server. */
    ServerNamespace getDefaultNamespace() { result = MkNamespace(this, "/") }

    /** Gets the namespace with the given path of this server. */
    ServerNamespace getNamespace(string path) { result = MkNamespace(this, path) }

    /**
     * Gets a data flow node that may refer to the socket.io server created at `srv`.
     */
    private DataFlow::SourceNode server(DataFlow::TypeTracker t) {
      result = this and t.start()
      or
      exists(DataFlow::TypeTracker t2, DataFlow::SourceNode pred | pred = server(t2) |
        result = pred.track(t2, t)
        or
        // invocation of a chainable method
        exists(DataFlow::MethodCallNode mcn, string m |
          m = "adapter" or
          m = "attach" or
          m = "bind" or
          m = "listen" or
          m = "onconnection" or
          m = "origins" or
          m = "path" or
          m = "serveClient" or
          m = "set" or
          m = EventEmitter::chainableMethod()
        |
          mcn = pred.getAMethodCall(m) and
          // exclude getter versions
          exists(mcn.getAnArgument()) and
          result = mcn and
          t = t2.continue()
        )
      )
    }

    override DataFlow::SourceNode ref() { result = server(DataFlow::TypeTracker::end()) }
  }

  /**
   * Gets the name of a chainable method on socket.io namespace objects, which servers forward
   * to their default namespace.
   */
  private string namespaceChainableMethod() {
    result = "binary" or
    result = "clients" or
    result = "compress" or
    result = "emit" or
    result = "in" or
    result = "send" or
    result = "to" or
    result = "use" or
    result = "write" or
    result = EventEmitter::chainableMethod()
  }

  class NamespaceObject extends SocketIOObject {
    ServerNamespace ns;

    NamespaceObject() {
      exists(ServerObject srv |
        // namespace lookup on `srv`
        this = srv.ref().getAPropertyRead("sockets") and
        ns = srv.getDefaultNamespace()
        or
        exists(DataFlow::MethodCallNode mcn, string path |
          mcn = srv.ref().getAMethodCall("of") and
          mcn.getArgument(0).mayHaveStringValue(path) and
          this = mcn and
          ns = MkNamespace(srv, path)
        )
        or
        // invocation of a method that `srv` forwards to its default namespace
        this = srv.ref().getAMethodCall(namespaceChainableMethod()) and
        ns = srv.getDefaultNamespace()
      )
    }

    ServerNamespace getNamespace() { result = ns }

    /**
     * Gets a data flow node that may refer to the socket.io namespace created at `ns`.
     */
    private DataFlow::SourceNode namespace(DataFlow::TypeTracker t) {
      t.start() and result = this
      or
      exists(DataFlow::SourceNode pred, DataFlow::TypeTracker t2 | pred = namespace(t2) |
        result = pred.track(t2, t)
        or
        // invocation of a chainable method
        result = pred.getAMethodCall(namespaceChainableMethod()) and
        t = t2.continue()
        or
        // invocation of chainable getter method
        exists(string m |
          m = "json" or
          m = "local" or
          m = "volatile"
        |
          result = pred.getAPropertyRead(m) and
          t = t2.continue()
        )
      )
    }

    override DataFlow::SourceNode ref() { result = namespace(DataFlow::TypeTracker::end()) }
  }

  class SocketObject extends SocketIOObject {
    ServerNamespace ns;

    SocketObject() {
      exists(DataFlow::SourceNode base, string connect, DataFlow::MethodCallNode on |
        (
          ns = any(ServerObject o | o.ref() = base).getDefaultNamespace() or
          ns = any(NamespaceObject o | o.ref() = base).getNamespace()
        ) and
        (connect = "connect" or connect = "connection")
      |
        on = base.getAMethodCall(EventEmitter::on()) and
        on.getArgument(0).mayHaveStringValue(connect) and
        this = on.getCallback(1).getParameter(0)
      )
    }

    /** Gets the namespace to which this socket belongs. */
    ServerNamespace getNamespace() { result = ns }

    /**
     * Gets a data flow node that may refer to a socket.io socket belonging to namespace `ns`.
     */
    private DataFlow::SourceNode socket(DataFlow::TypeTracker t) {
      result = this and t.start()
      or
      exists(DataFlow::SourceNode pred, DataFlow::TypeTracker t2 | pred = socket(t2) |
        result = pred.track(t2, t)
        or
        // invocation of a chainable method
        exists(string m |
          m = "binary" or
          m = "compress" or
          m = "disconnect" or
          m = "emit" or
          m = "in" or
          m = "join" or
          m = "leave" or
          m = "send" or
          m = "to" or
          m = "use" or
          m = "write" or
          m = EventEmitter::chainableMethod()
        |
          result = pred.getAMethodCall(m) and
          t = t2.continue()
        )
        or
        // invocation of a chainable getter method
        exists(string m |
          m = "broadcast" or
          m = "json" or
          m = "local" or
          m = "volatile"
        |
          result = pred.getAPropertyRead(m) and
          t = t2.continue()
        )
      )
    }

    override DataFlow::SourceNode ref() { result = socket(DataFlow::TypeTracker::end()) }
  }

  /**
   * A data flow node representing an API call that receives data from a client.
   */
  class ReceiveNode extends EventEmitter::EventRegistration::Range {
    override SocketObject emitter;

    ReceiveNode() { this = emitter.ref().getAMethodCall(EventEmitter::on()) }

    /** Gets the socket through which data is received. */
    SocketObject getSocket() { result = emitter }

    /** Gets the callback that handles data received from a client. */
    private DataFlow::FunctionNode getListener() { result = getCallback(1) }

    /** Gets the `i`th parameter through which data is received from a client. */
    override DataFlow::SourceNode getReceivedItem(int i) {
      exists(DataFlow::FunctionNode cb | cb = getListener() and result = cb.getParameter(i) |
        // exclude last parameter if it looks like a callback
        result != cb.getLastParameter() or not exists(result.getAnInvocation())
      )
    }

    /** Gets the acknowledgment callback, if any. */
    DataFlow::SourceNode getAck() {
      result = getListener().getLastParameter() and
      exists(result.getAnInvocation())
    }
  }

  /**
   * A data flow node representing data received from a client, viewed as remote user input.
   */
  private class ReceivedItemAsRemoteFlow extends RemoteFlowSource {
    ReceivedItemAsRemoteFlow() { this = any(ReceiveNode rercv).getReceivedItem(_) }

    override string getSourceType() { result = "socket.io client data" }

    override predicate isUserControlledObject() { any() }
  }

  /**
   * A data flow node representing an API call that sends data to a client.
   */
  class SendNode extends DataFlow::MethodCallNode, EventEmitter::EventDispatch::Range {
    override SocketIOObject emitter;
    int firstDataIndex;

    SendNode() {
      exists(string m | this = emitter.ref().getAMethodCall(m) |
        // a call to `emit`
        m = "emit" and
        firstDataIndex = 1
        or
        // a call to `send` or `write`
        (m = "send" or m = "write") and
        firstDataIndex = 0
      )
    }

    /**
     * Gets the socket through which data is sent to the client.
     *
     * This predicate is not defined for broadcasting sends.
     */
    SocketObject getSocket() { result = emitter }

    /**
     * Gets the namespace to which data is sent.
     */
    ServerNamespace getNamespace() {
      result = emitter.(ServerObject).getDefaultNamespace() or
      result = emitter.(NamespaceObject).getNamespace() or
      result = emitter.(SocketObject).getNamespace()
    }

    /** Gets the event name associated with the data, if it can be determined. */
    override string getChannel() {
      if firstDataIndex = 1 then getArgument(0).mayHaveStringValue(result) else result = "message"
    }

    /** Gets the `i`th argument through which data is sent to the client. */
    override DataFlow::Node getSentItem(int i) {
      result = getArgument(i + firstDataIndex) and
      i >= 0 and
      (
        // exclude last argument if it looks like a callback
        result != getLastArgument() or not exists(getAck())
      )
    }

    /** Gets the acknowledgment callback, if any. */
    DataFlow::FunctionNode getAck() {
      // acknowledgments are only available when sending through a socket
      exists(getSocket()) and
      result = getLastArgument().getALocalSource()
    }

    /** Gets a client-side node that may be receiving the data sent here. */
    SocketIOClient::ReceiveNode getAReceiver() {
      // TODO: Replace when I do the TaintStep.
      result.getSocket().getATargetNamespace() = getNamespace() and
      not result.getChannel() != getChannel()
    }
  }

  /** A socket.io namespace, identified by its server and its path. */
  private newtype TNamespace =
    MkNamespace(ServerObject srv, string path) {
      path = "/"
      or
      srv.ref().getAMethodCall("of").getArgument(0).mayHaveStringValue(path)
    }

  /** A socket.io namespace. */
  class ServerNamespace extends TNamespace {
    ServerObject srv;
    string path;

    ServerNamespace() { this = MkNamespace(srv, path) }

    /** Gets the server to which this namespace belongs. */
    ServerObject getServer() { result = srv }

    /** Gets the path of this namespace. */
    string getPath() { result = path }

    /** Gets a textual representation of this namespace. */
    string toString() { result = "socket.io namespace with path '" + path + "'" }
  }
}

/**
 * Provides classes for working with client-side socket.io code
 * (npm package `socket.io-client`).
 */
module SocketIOClient {
  abstract private class SocketIOObject extends DataFlow::SourceNode,
    EventEmitter::EventEmitterRange::Range { }

  /** A socket object. */
  class SocketObject extends SocketIOObject, DataFlow::InvokeNode {
    SocketObject() {
      exists(DataFlow::SourceNode io |
        io = DataFlow::globalVarRef("io") or
        io = DataFlow::globalVarRef("io").getAPropertyRead("connect") or
        io = DataFlow::moduleImport("io") or
        io = DataFlow::moduleMember("io", "connect") or
        io = DataFlow::moduleImport("socket.io-client") or
        io = DataFlow::moduleMember("socket.io-client", "connect")
      |
        this = io.getAnInvocation()
      )
    }

    /**
     * Gets a data flow node that may refer to the socket.io socket created at `invk`.
     */
    private DataFlow::SourceNode socket(DataFlow::TypeTracker t) {
      t.start() and result = this
      or
      exists(DataFlow::TypeTracker t2 | result = socket(t2).track(t2, t))
    }

    override DataFlow::SourceNode ref() { result = socket(DataFlow::TypeTracker::end()) }

    /** Gets the path of the namespace this socket belongs to, if it can be determined. */
    string getNamespacePath() {
      // the path name of the specified URL
      exists(string url, string pathRegex |
        this.getArgument(0).mayHaveStringValue(url) and
        pathRegex = "(?<!/)/(?!/)[^?#]*"
      |
        result = url.regexpFind(pathRegex, 0, _)
        or
        // if the URL does not specify an explicit path, it defaults to "/"
        not exists(url.regexpFind(pathRegex, _, _)) and
        result = "/"
      )
      or
      // if no URL is specified, the path defaults to "/"
      not exists(this.getArgument(0)) and
      result = "/"
    }

    /**
     * Gets a server this socket may be communicating with.
     *
     * To avoid matching sockets with unrelated servers, we restrict the search to
     * servers defined in the same npm package. Furthermore, the server is required
     * to have a namespace with the same path as the namespace of this socket, if
     * it can be determined.
     */
    SocketIO::ServerObject getATargetServer() {
      getPackage(result) = getPackage(this) and
      (
        not exists(getNamespacePath()) or
        exists(result.getNamespace(getNamespacePath()))
      )
    }

    /** Gets a namespace this socket may be communicating with. */
    SocketIO::ServerNamespace getATargetNamespace() {
      result = getATargetServer().getNamespace(getNamespacePath())
      or
      // if the namespace of this socket cannot be determined, overapproximate
      not exists(getNamespacePath()) and
      result = getATargetServer().getNamespace(_)
    }

    /** Gets a server-side socket this client-side socket may be communicating with. */
    SocketIO::SocketObject getATargetSocket() { result.getNamespace() = getATargetNamespace() }
  }

  /**
   * Gets the NPM package that contains `nd`.
   */
  private NPMPackage getPackage(DataFlow::SourceNode nd) { result.getAFile() = nd.getFile() }

  /**
   * A data flow node representing an API call that receives data from the server.
   */
  class ReceiveNode extends DataFlow::MethodCallNode, EventEmitter::EventRegistration::Range {
    override SocketObject emitter;

    ReceiveNode() { this = emitter.ref().getAMethodCall(EventEmitter::on()) }

    /** Gets the socket through which data is received. */
    SocketObject getSocket() { result = emitter }

    /** Gets the event name associated with the data, if it can be determined. */
    override string getChannel() { getArgument(0).mayHaveStringValue(result) }

    private DataFlow::SourceNode getListener(DataFlow::TypeBackTracker t) {
      t.start() and
      result = getArgument(1).getALocalSource()
      or
      exists(DataFlow::TypeBackTracker t2 | result = getListener(t2).backtrack(t2, t))
    }

    /** Gets the callback that handles data received from the server. */
    private DataFlow::FunctionNode getListener() {
      result = getListener(DataFlow::TypeBackTracker::end())
    }

    /** Gets the `i`th parameter through which data is received from the server. */
    override DataFlow::SourceNode getReceivedItem(int i) {
      exists(DataFlow::FunctionNode cb | cb = getListener() and result = cb.getParameter(i) |
        // exclude the last parameter if it looks like a callback
        result != cb.getLastParameter() or not exists(result.getAnInvocation())
      )
    }

    /** Gets the acknowledgment callback, if any. */
    DataFlow::SourceNode getAck() {
      result = getListener().getLastParameter() and
      exists(result.getAnInvocation())
    }
  }

  /**
   * A data flow node representing an API call that sends data to the server.
   */
  class SendNode extends DataFlow::MethodCallNode, EventEmitter::EventDispatch::Range {
    override SocketObject emitter;
    int firstDataIndex;

    SendNode() {
      exists(string m | this = emitter.ref().getAMethodCall(m) |
        // a call to `emit`
        m = "emit" and
        firstDataIndex = 1
        or
        // a call to `send` or `write`
        (m = "send" or m = "write") and
        firstDataIndex = 0
      )
    }

    /**
     * Gets the socket through which data is sent to the server.
     */
    SocketObject getSocket() { result = emitter }

    /**
     * Gets the path of the namespace to which data is sent, if it can be determined.
     */
    string getNamespacePath() { result = emitter.getNamespacePath() }

    /** Gets the event name associated with the data, if it can be determined. */
    override string getChannel() {
      if firstDataIndex = 1 then getArgument(0).mayHaveStringValue(result) else result = "message"
    }

    /** Gets the `i`th argument through which data is sent to the server. */
    override DataFlow::Node getSentItem(int i) {
      result = getArgument(i + firstDataIndex) and
      i >= 0 and
      (
        // exclude last argument if it looks like a callback
        result != getLastArgument() or not exists(getAck())
      )
    }

    /** Gets the acknowledgment callback, if any. */
    DataFlow::FunctionNode getAck() { result = getLastArgument().getALocalSource() }

    /** Gets a server-side node that may be receiving the data sent here. */
    override SocketIO::ReceiveNode getAReceiver() {
      result.getSocket().getNamespace() = getSocket().getATargetNamespace() and
      not result.getChannel() != getChannel()
    }
  }
}

/** A data flow step through socket.io sockets. */
private class SocketIoStep extends DataFlow::AdditionalFlowStep {
  DataFlow::Node pred;
  DataFlow::Node succ;

  SocketIoStep() {
    (
      exists(SocketIO::SendNode send, SocketIOClient::ReceiveNode recv, int i |
        recv = send.getAReceiver()
      |
        pred = send.getSentItem(i) and
        succ = recv.getReceivedItem(i)
        or
        pred = recv.getAck().getACall().getArgument(i) and
        succ = send.getAck().getParameter(i)
      )
      or
      exists(SocketIOClient::SendNode send, SocketIO::ReceiveNode recv, int i |
        recv = send.getAReceiver()
      |
        pred = send.getSentItem(i) and
        succ = recv.getReceivedItem(i)
        or
        pred = recv.getAck().getACall().getArgument(i) and
        succ = send.getAck().getParameter(i)
      )
    ) and
    this = pred
  }

  override predicate step(DataFlow::Node predNode, DataFlow::Node succNode) {
    predNode = pred and succNode = succ
  }
}
