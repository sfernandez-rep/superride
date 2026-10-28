// SPDX-License-Identifier: AGPL-3.0-only
package org.rstudio.studio.client.workbench.views.superrstudio;
import com.google.gwt.core.client.JavaScriptObject;
import com.google.gwt.core.client.JsArrayString;
public class ScatterResult extends JavaScriptObject
{
   protected ScatterResult() {}
   public final native boolean enabled() /*-{ return this.enabled === true; }-*/;
   public final native JsArrayString datasets() /*-{ return this.datasets || []; }-*/;
   public final native JsArrayString columns() /*-{ return this.columns || []; }-*/;
   public final native String revision() /*-{ return this.revision || ''; }-*/;
   public final native String code() /*-{ return this.code || ''; }-*/;
   public final native String warnings() /*-{ return (this.warnings || []).join('\n'); }-*/;
   public final native String provenance() /*-{
      return '# SuperRStudio ' + this.spec.kind + ' v' + this.spec.schema_version +
         '\n# Specification: ' + JSON.stringify(this.spec) +
         '\n# R: ' + this.r_version + '; ggplot2: ' + this.ggplot2_version + '\n';
   }-*/;
}
