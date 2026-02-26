This repo will be a signal viewer for NDI-matlab.

It works with https://github.com/VH-Lab/NDI-matlab. You will need to download and read the repo at branch enhancement/pyraviewer where we are co-developing the base library functionality. It also works with a repo at https://github.com/VH-Lab/Pyraview . You will need to download and read that repo as well.

The key piece is an application at src/ndi/+ndi/+app/pyraview.

Add a function at src/ndi/+ndi/+app/+pyraview/getData.m

This should take as input a probe (ndi.probe) and an ndi.document of type pyraview and open a fileless pyraview.Dataset object (from the Pyraview repo). It should also take as input the t0 and t1 of the display data to read. getData should return data from t0-delta to t1+delta, where delta is (t1-t0) (that is, one aperture earlier and one aperture later). It should take as input the pixelSpan of the axis window that is displaying the data.


It should call the Dataset methods to find the level and samples to read, and then use the open binary file methods of NDI to open the right file and the file_read method (Pyramid repo) to actually read the data.

Note that there is NO problem with the function being at src/ndi/+ndi/+app/+pyraview/getData.m when there is another function called src/ndi/+ndi/+app/pyraview.m. In Matlab the + just indicates a namespace, it does not imply any package relationship (unlike python)


Add this prompt to the agents folder (prompt2.md).