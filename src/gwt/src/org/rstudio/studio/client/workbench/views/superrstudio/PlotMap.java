// SPDX-License-Identifier: AGPL-3.0-only
package org.rstudio.studio.client.workbench.views.superrstudio;

import com.google.gwt.core.client.JavaScriptObject;
import com.google.gwt.core.client.JsArray;
import com.google.gwt.core.client.JsArrayNumber;

// The interactive preview produced by .rs.superrstudioInteractive: an image
// rendered by R (SVG, or PNG for large data) and a map of its editable
// elements. All coordinates are fractions of the image, origin top left.
public class PlotMap extends JavaScriptObject
{
   protected PlotMap() {}

   public final native String image() /*-{ return this.image || ''; }-*/;
   public final native String format() /*-{ return this.format || 'svg'; }-*/;
   public final native int width() /*-{ return this.width || 0; }-*/;
   public final native int height() /*-{ return this.height || 0; }-*/;
   public final native JsArray<Region> regions() /*-{ return this.regions || []; }-*/;
   public final native JsArray<Element> elements() /*-{ return this.elements || []; }-*/;

   // An image the browser renders without executing anything: SVG loaded
   // through <img> never runs scripts, and PNG is plain pixels.
   public final native String dataUri() /*-{
      return this.format === 'png'
         ? 'data:image/png;base64,' + this.image
         : 'data:image/svg+xml;charset=utf-8,' + encodeURIComponent(this.image);
   }-*/;

   // A gtable layout cell: title, axis titles, axes, legend, strips, panels.
   public static class Region extends JavaScriptObject
   {
      protected Region() {}
      public final native String role() /*-{ return this.role || ''; }-*/;
      // left, top, right, bottom
      public final native JsArrayNumber box() /*-{ return this.box || []; }-*/;
   }

   // Layer geometry: "points" (x,y pairs), "path" (polyline), "polygon",
   // or "rects" (left, top, right, bottom quadruples).
   public static class Element extends JavaScriptObject
   {
      protected Element() {}
      public final native String role() /*-{ return this.role || ''; }-*/;
      public final native String shape() /*-{ return this.shape || ''; }-*/;
      public final native JsArrayNumber coords() /*-{ return this.coords || []; }-*/;
   }
}
