// SPDX-License-Identifier: AGPL-3.0-only
package org.rstudio.studio.client.workbench.views.superrstudio;
import com.google.gwt.core.client.JavaScriptObject;
import com.google.gwt.core.client.JsArray;
import com.google.gwt.core.client.JsArrayString;
public class ScatterResult extends JavaScriptObject
{
   protected ScatterResult() {}
   public final native boolean enabled() /*-{ return this.enabled === true; }-*/;
   public final native JsArrayString datasets() /*-{ return this.datasets || []; }-*/;
   public final native JsArrayString columns() /*-{ return this.columns || []; }-*/;
   public final native JsArrayString colourColumns() /*-{ return this.colour_columns || []; }-*/;
   public final native JsArrayString discreteColumns() /*-{ return this.discrete_columns || []; }-*/;
   public final native String revision() /*-{ return this.revision || ''; }-*/;
   public final native String code() /*-{ return this.code || ''; }-*/;
   public final native String modelCode() /*-{ return this.model_code || ''; }-*/;
   public final native JsArray<FitEntry> fitSummary() /*-{ return this.fit_summary || []; }-*/;
   public final native String warnings() /*-{ return (this.warnings || []).join('\n'); }-*/;
   public final native String provenance() /*-{
      return '# SuperRStudio ' + this.spec.kind + ' v' + this.spec.schema_version +
         '\n# Specification: ' + JSON.stringify(this.spec) +
         '\n# R: ' + this.r_version + '; ggplot2: ' + this.ggplot2_version + '\n';
   }-*/;

   // One fitted group, as computed by .rs.superrstudioFitSummary (stats::lm or
   // stats::loess). Statistics that were not estimable are absent, never zero.
   public static class FitEntry extends JavaScriptObject
   {
      protected FitEntry() {}
      public final native String group() /*-{ return this.group || ''; }-*/;
      public final native int n() /*-{ return this.n || 0; }-*/;
      public final native String method() /*-{ return this.method || ''; }-*/;
      public final native boolean hasStatistics() /*-{ return typeof this.r_squared === 'number'; }-*/;
      public final native String equation() /*-{ return this.equation || ''; }-*/;
      public final native String note() /*-{ return this.note || ''; }-*/;
      public final native String rSquared() /*-{ return @org.rstudio.studio.client.workbench.views.superrstudio.ScatterResult::format(D)(this.r_squared); }-*/;
      public final native String adjRSquared() /*-{ return @org.rstudio.studio.client.workbench.views.superrstudio.ScatterResult::format(D)(this.adj_r_squared); }-*/;
      public final native String slopePValue() /*-{
         return typeof this.slope_p_value === 'number' ? @org.rstudio.studio.client.workbench.views.superrstudio.ScatterResult::format(D)(this.slope_p_value) : 'NA';
      }-*/;
      public final native String sigma() /*-{ return @org.rstudio.studio.client.workbench.views.superrstudio.ScatterResult::format(D)(this.sigma); }-*/;
      public final native String span() /*-{ return String(this.span); }-*/;
   }

   // Four significant digits, as R's signif(x, 4).
   static native String format(double value) /*-{
      return isFinite(value) ? String(Number(value.toPrecision(4))) : 'NA';
   }-*/;
}
