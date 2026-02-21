# Pingometer

Pingometer is a [SwiftBar](https://swiftbar.app/) plugin that displays network stability in the menu bar.

There are times when you’re on a call with someone and suddenly frames drop, and you lose audio. In those moments, I always wonder: was it my connection or theirs? That was the main idea behind the app. More generally, I just like knowing how stable my internet connection is.

It has a single dependency on `curl`, because `ping` doesn’t work well with some VPNs.

## How it works

On a timer, Pingometer sends a tiny request using `curl` and measures how long it takes to complete. It then turns those timings into a simple stability signal:

- **Low and consistent times** → connection looks stable  
- **Spikes / big variation** → brief hiccups (often felt as dropped audio/video frames)  
- **Timeouts / failed requests** → likely packet loss or a temporary outage  

This is not a full diagnostic tool—just a lightweight “is my connection behaving right now?” indicator you can glance at while on calls.

## Screenshot

![Pingometer screenshot](./screenshot.png)
