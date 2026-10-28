// SPDX-License-Identifier: AGPL-3.0-only
package org.rstudio.studio.client.workbench.views.superrstudio;
import org.rstudio.studio.client.server.ServerRequestCallback;
public interface SuperRStudioServerOperations
{
   void superrstudioData(String operation, String dataset, String revision,
                        String x, String y, ServerRequestCallback<ScatterResult> callback);
}
