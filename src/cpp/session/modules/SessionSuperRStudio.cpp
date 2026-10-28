// SuperRStudio experimental visual workflow. SPDX-License-Identifier: AGPL-3.0-only
#include "SessionSuperRStudio.hpp"
#include <core/system/Environment.hpp>
#include <r/RErrorCategory.hpp>
#include <r/RExec.hpp>
#include <r/RJson.hpp>
#include <r/RSexp.hpp>
#include <session/SessionModuleContext.hpp>

namespace rstudio { namespace session { namespace modules { namespace superrstudio {
using namespace core;
namespace {
bool s_enabled = false;

Error dataRequest(const json::JsonRpcRequest& request, json::JsonRpcResponse* response)
{
   std::string operation, dataset, revision, x, y;
   Error error = json::readParams(request.params, &operation, &dataset, &revision, &x, &y);
   if (error)
      return error;
   if (operation == "status" || !s_enabled)
   {
      json::Object status;
      status["enabled"] = s_enabled;
      response->setResult(status);
      return Success();
   }

   // Do not force promises or execute active bindings while discovering data.
   // All R access stays on this synchronous RPC's session thread.
   std::vector<std::string> names, available;
   r::sexp::listEnvironment(R_GlobalEnv, false, false, &names);
   for (const std::string& name : names)
   {
      if (r::sexp::getBindingType(name, R_GlobalEnv) != r::sexp::BindingType::Normal)
         continue;
      SEXP value = r::sexp::findVar(name, R_GlobalEnv);
      if (TYPEOF(value) == VECSXP && Rf_inherits(value, "data.frame"))
         available.push_back(name);
   }
   r::sexp::Protect protect;
   SEXP result = R_NilValue;
   error = r::exec::RFunction(".rs.superrstudioDataRpc")
      .addParam(operation).addParam(dataset).addParam(revision)
      .addParam(x).addParam(y).addParam(available).call(&result, &protect);
   if (error)
      return error;
   json::Value value;
   error = r::json::jsonValueFromObject(result, &value);
   if (error)
      return error;

   // validation failures are written for the user; the client shows this
   // message (client info) in place of the error summary
   if (value.isObject() && value.getObject().hasMember("error"))
   {
      std::string message = value.getObject()["error"].getString();
      response->setError(r::rCodeExecutionError(message, ERROR_LOCATION), json::Value(message));
      return Success();
   }

   response->setResult(value);
   return Success();
}
} // namespace

Error initialize()
{
   s_enabled = core::system::getenv("SUPER_RSTUDIO_EXPERIMENTAL") == "1";
   if (s_enabled)
   {
      Error error = module_context::sourceModuleRFile("SessionSuperRStudio.R");
      if (error)
         return error;
   }
   return module_context::registerRpcMethod("superrstudio_data", dataRequest);
}
}}}}
