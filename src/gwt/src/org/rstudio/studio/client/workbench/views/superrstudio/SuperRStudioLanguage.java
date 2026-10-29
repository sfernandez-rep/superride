// SPDX-License-Identifier: AGPL-3.0-only
package org.rstudio.studio.client.workbench.views.superrstudio;

import com.google.gwt.core.client.GWT;
import org.rstudio.studio.client.workbench.prefs.model.LocaleCookie;

// The language of SuperRStudio's own windows. RStudio's GWT build compiles
// the locales for which every upstream interface has resources (en, fr), so
// Spanish is chosen at run time from the user-interface language preference
// (mirrored in the LOCALE cookie): SuperRStudio features use the generated
// XxxMessagesEs classes, upstream text stays in its compiled language.
// Numbers, dates and R code are never localized here.
public class SuperRStudioLanguage
{
   public static boolean spanish()
   {
      return "es".equals(LocaleCookie.getUiLanguage());
   }

   public static ScatterMessages scatter()
   {
      return spanish() ? new ScatterMessagesEs() : GWT.create(ScatterMessages.class);
   }

   public static LfqMessages lfq()
   {
      return spanish() ? new LfqMessagesEs() : GWT.create(LfqMessages.class);
   }

   public static DependencyMessages deps()
   {
      return spanish() ? new DependencyMessagesEs() : GWT.create(DependencyMessages.class);
   }

   // Replaces {0}, {1}, ... like the plain MessageFormat placeholders used by
   // the interfaces (no number or date formats are used in them).
   public static String format(String pattern, String... args)
   {
      StringBuilder out = new StringBuilder();
      int i = 0;
      while (i < pattern.length())
      {
         char c = pattern.charAt(i);
         int close = c == '{' ? pattern.indexOf('}', i) : -1;
         if (close > i + 1 && pattern.substring(i + 1, close).matches("[0-9]+"))
         {
            int index = Integer.parseInt(pattern.substring(i + 1, close));
            out.append(index < args.length && args[index] != null ? args[index] : "");
            i = close + 1;
         }
         else
         {
            out.append(c);
            i++;
         }
      }
      return out.toString();
   }
}
