// SPDX-License-Identifier: AGPL-3.0-only
package org.rstudio.studio.client.workbench.views.superrstudio;
import com.google.gwt.json.client.JSONObject;
import org.rstudio.studio.client.server.ServerRequestCallback;
public interface SuperRStudioServerOperations
{
   // appearance: scatter appearance settings (validated in the session); may be null
   void superrstudioData(String operation, String dataset, String revision,
                        String x, String y, JSONObject appearance,
                        ServerRequestCallback<ScatterResult> callback);
}
