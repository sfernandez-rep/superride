// SPDX-License-Identifier: AGPL-3.0-only
package org.rstudio.studio.client.workbench.views.superrstudio;

import java.util.ArrayList;
import java.util.List;

import com.google.gwt.core.client.JsArray;
import com.google.gwt.core.client.JsArrayNumber;
import com.google.gwt.dom.client.Document;
import com.google.gwt.dom.client.Style.Cursor;
import com.google.gwt.dom.client.Style.Position;
import com.google.gwt.dom.client.Style.Unit;
import com.google.gwt.event.dom.client.ClickEvent;
import com.google.gwt.event.dom.client.ContextMenuEvent;
import com.google.gwt.event.dom.client.KeyCodes;
import com.google.gwt.event.dom.client.KeyDownEvent;
import com.google.gwt.event.dom.client.MouseMoveEvent;
import com.google.gwt.user.client.ui.AbsolutePanel;
import com.google.gwt.user.client.ui.Composite;
import com.google.gwt.user.client.ui.HTML;
import com.google.gwt.user.client.ui.Image;

// The editor's interactive plot preview. The image is R's own rendering;
// selection uses the element map that came with it (PlotMap), never the
// image's pixels. A click selects an element, a right-click (or Enter,
// Shift+F10 or the context-menu key on the focused preview) opens its
// properties, and the arrow keys move the selection between elements.
public class InteractivePreview extends Composite
{
   public interface Listener
   {
      void onSelect(String role);
      // open the properties of an element at page coordinates
      void onEdit(String role, int pageX, int pageY);
   }

   // Element roles in keyboard order (also the hit-testing order below).
   public static final String[] ROLES = {"title", "points", "lines", "fit", "bars", "boxes",
      "density", "x_label", "x_axis", "y_label", "y_axis", "legend", "strip", "panel"};

   public InteractivePreview(Listener listener)
   {
      listener_ = listener;
      panel_.getElement().getStyle().setPosition(Position.RELATIVE);
      panel_.getElement().setId("superrstudio_interactive");
      panel_.getElement().setTabIndex(0);
      panel_.getElement().setAttribute("role", "application");
      panel_.getElement().setAttribute("aria-roledescription", "plot preview");
      image_.getElement().setAttribute("alt", "");
      image_.getElement().setAttribute("draggable", "false");
      image_.setVisible(false);
      panel_.add(image_, 0, 0);
      highlight_.getElement().setId("superrstudio_highlight");
      highlight_.setStyleName("superrstudio-highlight");
      highlight_.getElement().getStyle().setProperty("pointerEvents", "none");
      highlight_.getElement().getStyle().setProperty("outline", "2px dashed #0072B2");
      highlight_.getElement().getStyle().setProperty("boxShadow", "0 0 0 1px #FFFFFF");
      highlight_.setVisible(false);
      panel_.add(highlight_, 0, 0);
      setSize(480, 360);

      panel_.addDomHandler(e -> hover(e), MouseMoveEvent.getType());
      panel_.addDomHandler(e -> {
         Hit hit = hitTest(e.getRelativeX(panel_.getElement()), e.getRelativeY(panel_.getElement()));
         select(hit);
         panel_.getElement().focus();
      }, ClickEvent.getType());
      panel_.addDomHandler(e -> contextMenu(e), ContextMenuEvent.getType());
      panel_.addDomHandler(e -> key(e), KeyDownEvent.getType());
      initWidget(panel_);
   }

   // The preview's lower-right corner resizes it (the canvas). Only drags by
   // the user are reported, once they settle; sizes set by a new plot are not.
   public void setResizable(ResizeListener listener)
   {
      resizeListener_ = listener;
      panel_.getElement().getStyle().setProperty("resize", "both");
      panel_.getElement().getStyle().setOverflow(com.google.gwt.dom.client.Style.Overflow.HIDDEN);
      panel_.getElement().getStyle().setProperty("minWidth", "96px");
      panel_.getElement().getStyle().setProperty("minHeight", "96px");
      panel_.getElement().getStyle().setProperty("border", "1px dashed rgba(127, 127, 127, 0.6)");
      image_.getElement().getStyle().setProperty("width", "100%");
      image_.getElement().getStyle().setProperty("height", "100%");
      observe(panel_.getElement());
   }

   public interface ResizeListener
   {
      void onResized(int width, int height);
   }

   private native void observe(com.google.gwt.dom.client.Element element) /*-{
      var self = this;
      var timer = null;
      if (!$wnd.ResizeObserver)
         return;
      new $wnd.ResizeObserver(function() {
         if (timer) $wnd.clearTimeout(timer);
         timer = $wnd.setTimeout($entry(function() {
            self.@org.rstudio.studio.client.workbench.views.superrstudio.InteractivePreview::resized(II)(
               element.clientWidth, element.clientHeight);
         }), 350);
      }).observe(element);
   }-*/;

   private void resized(int width, int height)
   {
      if (resizeListener_ == null || (Math.abs(width - width_) <= 1 && Math.abs(height - height_) <= 1))
         return;
      resizeListener_.onResized(width, height);
   }

   public void setPlot(PlotMap map)
   {
      map_ = map;
      setSize(map.width(), map.height());
      image_.setUrl(map.dataUri());
      image_.setVisible(true);
      image_.getElement().getStyle().setOpacity(1);
      roles_ = availableRoles();
      // keep the selection when the element still exists after a re-render
      Hit kept = selected_ == null ? null : find(selected_.role);
      select(kept);
   }

   // The image no longer reflects the settings; shown dimmed until replaced.
   public void setStale()
   {
      if (map_ != null)
         image_.getElement().getStyle().setOpacity(0.5);
   }

   public void clear()
   {
      map_ = null;
      roles_ = new ArrayList<>();
      image_.setVisible(false);
      select(null);
   }

   public boolean hasPlot()
   {
      return map_ != null;
   }

   public List<String> roles()
   {
      return roles_;
   }

   public String selectedRole()
   {
      return selected_ == null ? "" : selected_.role;
   }

   public void selectRole(String role)
   {
      select(find(role));
   }

   // Page position next to the selected element (for keyboard-opened menus).
   public int[] selectedPagePosition()
   {
      int left = panel_.getAbsoluteLeft(), top = panel_.getAbsoluteTop();
      if (selected_ == null)
         return new int[] {left + 8, top + 8};
      return new int[] {left + (int) selected_.box[0], top + (int) selected_.box[3] + 4};
   }

   private void setSize(int width, int height)
   {
      width_ = width;
      height_ = height;
      panel_.setPixelSize(width, height);
      if (resizeListener_ == null)
         image_.setPixelSize(width, height);
   }

   private ResizeListener resizeListener_;

   private void hover(MouseMoveEvent event)
   {
      Hit hit = hitTest(event.getRelativeX(panel_.getElement()), event.getRelativeY(panel_.getElement()));
      panel_.getElement().getStyle().setCursor(hit == null || "panel".equals(hit.role)
         ? Cursor.DEFAULT : Cursor.POINTER);
   }

   private void contextMenu(ContextMenuEvent event)
   {
      // always suppress the browser menu over the plot: it would offer to
      // save or copy the raster as if it were the editable plot
      event.preventDefault();
      event.stopPropagation();
      int pageX = event.getNativeEvent().getClientX() + Document.get().getScrollLeft();
      int pageY = event.getNativeEvent().getClientY() + Document.get().getScrollTop();
      Hit hit = hitTest(pageX - panel_.getAbsoluteLeft(), pageY - panel_.getAbsoluteTop());
      if (hit == null)
         return;
      select(hit);
      listener_.onEdit(hit.role, pageX, pageY);
   }

   private void key(KeyDownEvent event)
   {
      int code = event.getNativeKeyCode();
      boolean menu = code == KeyCodes.KEY_ENTER || code == KEY_CONTEXT_MENU ||
                     (code == KeyCodes.KEY_F10 && event.isShiftKeyDown());
      if (menu && selected_ != null)
      {
         event.preventDefault();
         int[] position = selectedPagePosition();
         listener_.onEdit(selected_.role, position[0], position[1]);
      }
      else if ((code == KeyCodes.KEY_RIGHT || code == KeyCodes.KEY_DOWN ||
                code == KeyCodes.KEY_LEFT || code == KeyCodes.KEY_UP) && !roles_.isEmpty())
      {
         event.preventDefault();
         int step = code == KeyCodes.KEY_RIGHT || code == KeyCodes.KEY_DOWN ? 1 : -1;
         int index = selected_ == null ? (step > 0 ? -1 : 0) : roles_.indexOf(selected_.role);
         index = (index + step + roles_.size()) % roles_.size();
         select(find(roles_.get(index)));
      }
   }

   private void select(Hit hit)
   {
      selected_ = hit;
      if (hit == null)
      {
         highlight_.setVisible(false);
         listener_.onSelect("");
         return;
      }
      double pad = 3;
      double left = Math.max(0, hit.box[0] - pad), top = Math.max(0, hit.box[1] - pad);
      double right = Math.min(width_, hit.box[2] + pad), bottom = Math.min(height_, hit.box[3] + pad);
      panel_.setWidgetPosition(highlight_, (int) left, (int) top);
      highlight_.getElement().getStyle().setWidth(Math.max(2, right - left), Unit.PX);
      highlight_.getElement().getStyle().setHeight(Math.max(2, bottom - top), Unit.PX);
      highlight_.setVisible(true);
      listener_.onSelect(hit.role);
   }

   // Hit testing (pixels) ----------------------------------------------------

   private static class Hit
   {
      Hit(String role, double[] box)
      {
         this.role = role;
         this.box = box;
      }

      final String role;
      final double[] box;   // left, top, right, bottom in pixels
   }

   private List<String> availableRoles()
   {
      List<String> roles = new ArrayList<>();
      for (String role : ROLES)
         if (find(role) != null)
            roles.add(role);
      return roles;
   }

   // The union of all of a role's geometry or regions.
   private Hit find(String role)
   {
      if (map_ == null)
         return null;
      double[] box = null;
      JsArray<PlotMap.Element> elements = map_.elements();
      for (int i = 0; i < elements.length(); i++)
         if (elements.get(i).role().equals(role))
            box = union(box, bounds(elements.get(i).coords()));
      JsArray<PlotMap.Region> regions = map_.regions();
      for (int i = 0; i < regions.length(); i++)
         if (regions.get(i).role().equals(role))
            box = union(box, bounds(regions.get(i).box()));
      return box == null ? null : new Hit(role, box);
   }

   private Hit hitTest(double x, double y)
   {
      if (map_ == null)
         return null;
      JsArray<PlotMap.Element> elements = map_.elements();
      String best = null;
      double bestDistance = 6;
      // points first: they are drawn on top and are the smallest targets
      for (int i = 0; i < elements.length(); i++)
      {
         PlotMap.Element element = elements.get(i);
         if (!"points".equals(element.shape()))
            continue;
         JsArrayNumber c = element.coords();
         for (int j = 0; j + 1 < c.length(); j += 2)
         {
            double d = Math.hypot(c.get(j) * width_ - x, c.get(j + 1) * height_ - y);
            if (d <= bestDistance)
            {
               bestDistance = d;
               best = element.role();
            }
         }
      }
      if (best != null)
         return find(best);
      bestDistance = 5;
      for (int i = 0; i < elements.length(); i++)
      {
         PlotMap.Element element = elements.get(i);
         if (!"path".equals(element.shape()))
            continue;
         double d = pathDistance(element.coords(), x, y);
         if (d <= bestDistance)
         {
            bestDistance = d;
            best = element.role();
         }
      }
      if (best != null)
         return find(best);
      for (int i = 0; i < elements.length(); i++)
      {
         PlotMap.Element element = elements.get(i);
         if ("rects".equals(element.shape()) && inRects(element.coords(), x, y))
            return find(element.role());
      }
      for (int i = 0; i < elements.length(); i++)
      {
         PlotMap.Element element = elements.get(i);
         if ("polygon".equals(element.shape()) && inPolygon(element.coords(), x, y))
            return find(element.role());
      }
      JsArray<PlotMap.Region> regions = map_.regions();
      String panel = null;
      for (int i = 0; i < regions.length(); i++)
      {
         JsArrayNumber b = regions.get(i).box();
         if (x >= b.get(0) * width_ && x <= b.get(2) * width_ &&
             y >= b.get(1) * height_ && y <= b.get(3) * height_)
         {
            if (!"panel".equals(regions.get(i).role()))
               return find(regions.get(i).role());
            panel = "panel";
         }
      }
      return panel == null ? null : find(panel);
   }

   // also covers rects: (left, top, right, bottom) are two corner points
   private double[] bounds(JsArrayNumber c)
   {
      if (c.length() < 2)
         return null;
      double[] box = {Double.MAX_VALUE, Double.MAX_VALUE, -Double.MAX_VALUE, -Double.MAX_VALUE};
      for (int j = 0; j + 1 < c.length(); j += 2)
      {
         double px = c.get(j) * width_, py = c.get(j + 1) * height_;
         box[0] = Math.min(box[0], px);
         box[1] = Math.min(box[1], py);
         box[2] = Math.max(box[2], px);
         box[3] = Math.max(box[3], py);
      }
      return box;
   }

   private static double[] union(double[] a, double[] b)
   {
      if (a == null) return b;
      if (b == null) return a;
      return new double[] {Math.min(a[0], b[0]), Math.min(a[1], b[1]),
                           Math.max(a[2], b[2]), Math.max(a[3], b[3])};
   }

   private double pathDistance(JsArrayNumber c, double x, double y)
   {
      double best = Double.MAX_VALUE;
      for (int j = 0; j + 3 < c.length(); j += 2)
      {
         double x1 = c.get(j) * width_, y1 = c.get(j + 1) * height_;
         double x2 = c.get(j + 2) * width_, y2 = c.get(j + 3) * height_;
         double dx = x2 - x1, dy = y2 - y1;
         double length = dx * dx + dy * dy;
         double t = length == 0 ? 0 : Math.max(0, Math.min(1, ((x - x1) * dx + (y - y1) * dy) / length));
         best = Math.min(best, Math.hypot(x1 + t * dx - x, y1 + t * dy - y));
      }
      return best;
   }

   private boolean inRects(JsArrayNumber c, double x, double y)
   {
      for (int j = 0; j + 3 < c.length(); j += 4)
      {
         double left = c.get(j) * width_, top = c.get(j + 1) * height_;
         double right = c.get(j + 2) * width_, bottom = c.get(j + 3) * height_;
         if (x >= Math.min(left, right) - 2 && x <= Math.max(left, right) + 2 &&
             y >= Math.min(top, bottom) - 2 && y <= Math.max(top, bottom) + 2)
            return true;
      }
      return false;
   }

   // even-odd ray casting
   private boolean inPolygon(JsArrayNumber c, double x, double y)
   {
      boolean inside = false;
      int n = c.length() / 2;
      for (int i = 0, j = n - 1; i < n; j = i++)
      {
         double xi = c.get(2 * i) * width_, yi = c.get(2 * i + 1) * height_;
         double xj = c.get(2 * j) * width_, yj = c.get(2 * j + 1) * height_;
         if ((yi > y) != (yj > y) && x < (xj - xi) * (y - yi) / (yj - yi) + xi)
            inside = !inside;
      }
      return inside;
   }

   private static final int KEY_CONTEXT_MENU = 93;
   private final Listener listener_;
   private final AbsolutePanel panel_ = new AbsolutePanel();
   private final Image image_ = new Image();
   private final HTML highlight_ = new HTML();
   private PlotMap map_;
   private List<String> roles_ = new ArrayList<>();
   private Hit selected_;
   private int width_, height_;
}
