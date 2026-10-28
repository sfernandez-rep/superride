// SPDX-License-Identifier: AGPL-3.0-only
package org.rstudio.studio.client.workbench.views.superrstudio;
import com.google.gwt.i18n.client.Messages;
public interface ScatterMessages extends Messages
{
   @DefaultMessage("Visual scatter plot") String title();
   @DefaultMessage("Scatter") String toolbarLabel();
   @DefaultMessage("Plot two numeric columns from a data frame in the current R session. The source data is preserved.") String help();
   @DefaultMessage("Data") String dataHeading();
   @DefaultMessage("Appearance") String appearanceHeading();
   @DefaultMessage("Dataset") String dataset();
   @DefaultMessage("X column") String xColumn();
   @DefaultMessage("Y column") String yColumn();
   @DefaultMessage("Colour by column (viridis scale)") String colourBy();
   @DefaultMessage("(none)") String colourByNone();
   @DefaultMessage("Plot title (optional)") String plotTitle();
   @DefaultMessage("X axis title (blank: column name)") String xLabel();
   @DefaultMessage("Y axis title (blank: column name)") String yLabel();
   @DefaultMessage("Point colour") String colour();
   @DefaultMessage("Point size") String size();
   @DefaultMessage("Point opacity") String opacity();
   @DefaultMessage("Theme") String theme();
   @DefaultMessage("Default (ggplot2)") String colourDefault();
   @DefaultMessage("Black") String colourBlack();
   @DefaultMessage("Orange") String colourOrange();
   @DefaultMessage("Sky blue") String colourSkyBlue();
   @DefaultMessage("Bluish green") String colourGreen();
   @DefaultMessage("Blue") String colourBlue();
   @DefaultMessage("Vermillion") String colourVermillion();
   @DefaultMessage("Reddish purple") String colourPurple();
   @DefaultMessage("Grey (ggplot2 default)") String themeGrey();
   @DefaultMessage("Black and white") String themeBw();
   @DefaultMessage("Minimal") String themeMinimal();
   @DefaultMessage("Classic") String themeClassic();
   @DefaultMessage("Light") String themeLight();
   @DefaultMessage("Undo") String undo();
   @DefaultMessage("Reset appearance") String reset();
   @DefaultMessage("Preview in Plots") String preview();
   @DefaultMessage("Open R code") String exportCode();
   @DefaultMessage("Refresh data") String refresh();
   @DefaultMessage("Close") String close();
   @DefaultMessage("Loading current data…") String loading();
   @DefaultMessage("No supported data frames. Create or import one in the R console, then refresh.") String noData();
   @DefaultMessage("Select numeric columns; this preview supports plain data frames up to 100,000 rows and 16 MiB.") String ready();
   @DefaultMessage("This data frame has no supported numeric columns.") String noColumns();
   @DefaultMessage("Working in the active R session…") String working();
   @DefaultMessage("Plot created in the Plots pane. The R code is shown below.") String plotted();
   @DefaultMessage("Reproducible R code") String codeLabel();
}
