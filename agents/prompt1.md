NDI-pyraview-matlab

This repo will be a signal viewer for NDI-matlab.

It works with https://github.com/VH-Lab/NDI-matlab. You will need to download and read the repo at branch enhancement/pyraviewer where we are co-developing the base library functionality. It also works with a repo at https://github.com/VH-Lab/Pyraview . You will need to download and read that repo as well.

The key piece will be a an application at src/ndi/+ndi/+app/pyraview. It will be a viewer that also frequently serves as its own call back function. I’ve included an example of such a function. We will not be using the matlab app maker or anything like that because it is harder to generate by hand. The function’s inputs should all be by name/value pairs using the arguments block. One input will be the session (type ndi.session, default ndi.session.empty() ). Another input will be ‘command’ (a character array, default value ‘Initialize’).

The window should have the title ‘pyraview: NDISESSIONREF’ where NDISESSIONREF is the reference of the ndi.session object.

In the very upper left, there should be a drop down menu with a static text title: "Probe:” next to it. This should list all probes of type ’n-trode’ which can be obtained from p = S.getprobes(’type’,’n-trode’) where S is the ndi.session object. The value that is printed in the drop down menu should be each probe’s element string p{i}.elementstring().  Next to that dropdown should be another drop down with a static text label called “epoch_id:” and there should be a list of the epochs from the probe obtained from et = p{i}.epochtable(); epoch_ids = {et.epoch_id}; There should be an empty slot with a spacer before the epochs are listed in the drop down. The empty one should be selected by default which means no drawing.  Next to that dropdown should be another drop down that says “band” and two choices should be ‘low’ and ‘high’. By default, ‘high’ should be selected.

Underneath these drop-downs should be a separator line.

Then, in the left 3/4 of the window and taking up 80% of the height of the window, should be a frame. The frame should have a set of axes, and, on the bottom, have two scroll bars, each the width of the axes; one should be on top of the other. The top scroll bar should have value from 1 to N, where N is either 100 or it is 10 times the number of viewing apertures of the data being plotted, with the current window axes being considered one aperture view. (Use 100 if there is no data being displayed at the moment). The bottom scroll bar will be a type of horizontal zoom with values from -100 to 100 and it begins at 0 in the middle. 0 means the view should span 100 seconds. A value of -10 means that it should span 10 seconds, a value of -20 means it should span 1 second, and so on. A value of +10 means the view should span 1000 seconds.

We will handle the drawing in the next set of instructions.

Save these instructions to a directory called agents with the filename prompt1.md

Here is the example application that partially serves as its own callback function.

[Example Code Omitted for Brevity - User provided cluster_spikewaves_gui code]
