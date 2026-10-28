// SPDX-License-Identifier: AGPL-3.0-only
package org.rstudio.studio.client.workbench.views.superrstudio;
import com.google.gwt.i18n.client.Messages;
public interface ScatterMessages extends Messages
{
   @DefaultMessage("Visual scatter plot") String title();
   @DefaultMessage("Scatter") String toolbarLabel();
   @DefaultMessage("Plot two numeric columns from a data frame in the current R session. The source data is preserved.") String help();
   @DefaultMessage("Dataset") String dataset();
   @DefaultMessage("X column") String xColumn();
   @DefaultMessage("Y column") String yColumn();
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
