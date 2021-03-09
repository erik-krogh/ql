/**
 * @name Template Object Injection
 * @description Instantiating a template using a user-controlled object is vulnerable to local file read and potential remote code execution.
 * @kind path-problem
 * @problem.severity error
 * @precision high
 * @id js/template-object-injection
 * @tags security
 *       external/cwe/cwe-073
 *       external/cwe/cwe-094
 */

import javascript
import DataFlow::PathGraph

from DataFlow::PathNode source, DataFlow::PathNode sink
where none()
select sink.getNode(), source, sink, "Template object injection due to $@.", source.getNode(),
  "user-provided value"
