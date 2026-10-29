// SPDX-License-Identifier: AGPL-3.0-only
package org.rstudio.studio.client.workbench.views.superrstudio;

import com.google.gwt.core.client.JavaScriptObject;
import com.google.gwt.core.client.JsArray;
import com.google.gwt.core.client.JsArrayNumber;
import com.google.gwt.core.client.JsArrayString;

// Results of the length-frequency (lfq_*) operations, read by field name:
// the shapes are defined in SessionSuperRStudioLfq.R.
public class LfqResult extends JavaScriptObject
{
   protected LfqResult() {}

   public final native boolean has(String key) /*-{
      return this[key] !== undefined && this[key] !== null;
   }-*/;

   public final native String str(String key) /*-{
      var value = this[key];
      return value === undefined || value === null ? '' : String(value);
   }-*/;

   public final native double num(String key) /*-{
      var value = this[key];
      return typeof value === 'number' ? value : NaN;
   }-*/;

   public final native boolean flag(String key) /*-{ return this[key] === true; }-*/;

   public final native JsArrayString strings(String key) /*-{ return this[key] || []; }-*/;

   public final native JsArrayNumber numbers(String key) /*-{ return this[key] || []; }-*/;

   public final native JsArray<LfqResult> list(String key) /*-{ return this[key] || []; }-*/;

   public final native LfqResult obj(String key) /*-{ return this[key] || {}; }-*/;
}
