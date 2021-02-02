using Toybox.WatchUi as Ui;
using Toybox.System as Sys;
using Toybox.Application as App;

const GOAL_METER_STYLE = [
	:MULTI_SEGMENTS,
	:SINGLE_SEGMENT,
	:HIDDEN
];

const NUM_SEGMENTS = 10;
const MIN_WHOLE_SEGMENT_HEIGHT = 5;

// Buffered drawing behaviour:
// - On initialisation: calculate clip width (non-trivial for arc shape); create buffers for empty and filled segments.
// - On setting current/max values: if max changes, re-calculate segment layout and set dirty buffer flag; if current changes, re-
//   calculate fill height.
// - On draw: if buffers are dirty, redraw them and clear flag; clip appropriate portion of each buffer to screen. Each buffer
//   contains all segments in appropriate colour, with separators. Maximum of 2 draws to screen on each draw() cycle.
class GoalMeter extends Ui.Drawable {

	private var mSide; // :left, :right.
	private var mShape; // :arc, :line.
	private var mStroke; // Stroke width.
	private var mWidth; // Clip width of meter.
	private var mHeight; // Clip height of meter.
	private var mSeparator; // Current stroke width of separator bars.
	private var mLayoutSeparator; // Stroke with of separator bars specified in layout.

	private var mSegments = 0; // Array of segment heights, in pixels, excluding separators.
	private var mFillHeight = 0; // Total height of filled segments, in pixels, including separators.
	private var mTargetHeight = 0; // Total height of the target gauge.
	private var mFillType = :FILL_1x; // Type of fill.

	private var mPaletteEmpty = null;
	private var mPalette1x = null;
	private var mPalette2x = null;
	private var mPaletteTarget = null;
	private var mBackgroundColour = 0;
	private var mMeterBackgroundColour = 0;
	private var mThemeColour = 0;

	(:buffered) private var mFilledBuffer1x; // Bitmap buffer containing all full segments.
	(:buffered) private var mFilledBuffer2x; // Bitmap buffer containing all full segments (2x the goal).
	(:buffered) private var mTargetBuffer; // Bitmap buffer containing the target gauge.
	(:buffered) private var mEmptyBuffer; // Bitmap buffer containing all empty segments.

	private var mBuffersNeedRecreate = true; // Buffers need to be recreated on next draw() cycle.
	private var mBuffersNeedRedraw = true; // Buffers need to be redrawn on next draw() cycle.

	private var mCurrentValue;
	private var mMaxValue;
	private var mTargetValue;
	private var mTargetMaxValue;

	function initialize(params) {
		Drawable.initialize(params);

		mSide = params[:side];
		mShape = params[:shape];
		mStroke = params[:stroke];
		mHeight = params[:height];
		mLayoutSeparator = params[:separator];
		
		mBackgroundColour = App.getApp().getProperty("BackgroundColour");
		mMeterBackgroundColour = App.getApp().getProperty("MeterBackgroundColour");
		mThemeColour = App.getApp().getProperty("ThemeColour");
		RefreshPalettes();

		// Read meter style setting to determine current separator width.
		onSettingsChanged();

		mWidth = getWidth();
	}

	function getWidth() {
		var width;
		
		var halfScreenWidth;
		var innerRadius;

		if (mShape == :arc) {
			halfScreenWidth = Sys.getDeviceSettings().screenWidth / 2; // DC not available; OK to use screenWidth from settings?
			innerRadius = halfScreenWidth - mStroke; 
			width = halfScreenWidth - Math.sqrt(Math.pow(innerRadius, 2) - Math.pow(mHeight / 2, 2));
			width = Math.ceil(width); // Round up to cover partial pixels.
		} else {
			width = mStroke;
		}

		return width;
	}

	function setValues(current, max, target, targetMax) {

		// If max value changes, recalculate and cache segment layout, and set mBuffersNeedRedraw flag. Can't redraw buffers here,
		// as we don't have reference to screen DC, in order to determine its dimensions - do this later, in draw() (already in
		// draw cycle, so no real benefit in fetching screen width). Clear current value to force recalculation of fillHeight.
		if ((max != mMaxValue) || (targetMax != mTargetMaxValue)) {
			mCurrentValue = current;
			mMaxValue = max;
			mTargetValue = target;
			mTargetMaxValue = targetMax;

			mSegments = getSegments(NUM_SEGMENTS);
			mBuffersNeedRedraw = true;
		}

		// Only recompute if the buffers need redrawing, the current value changes more than 1% of the max or
		// the current value moves back.

		if (mBuffersNeedRedraw ||
			(current < mCurrentValue) ||
			((current - mCurrentValue) >= (mMaxValue / 100))) {
			mCurrentValue = current;

			var i;
			var currentValueToScale = 0;
	
			if (mCurrentValue <= mMaxValue) {
				mFillType = :FILL_1x;
				currentValueToScale = mCurrentValue;
			}
			else if (mCurrentValue <= (2 * mMaxValue)) {
				mFillType = :FILL_2x;
				currentValueToScale = ((mCurrentValue - 1) % mMaxValue) + 1;
			}
			else {
				mFillType = :FILL_2x;
				currentValueToScale = mMaxValue;
			}
	
			var totalSegmentHeight = 0;
			for (i = 0; i < mSegments.size(); ++i) {
				totalSegmentHeight += mSegments[i];
			}
	
			var remainingFillHeight = Math.floor((currentValueToScale * 1.0 / mMaxValue) * totalSegmentHeight); // Excluding separators.
			mFillHeight = remainingFillHeight;
			
			for (i = 0; i < mSegments.size(); ++i) {
				remainingFillHeight -= mSegments[i];
				if (remainingFillHeight > 0) {
					mFillHeight += mSeparator; // Fill extends beyond end of this segment, so add separator height.
				} else {
					break; // Fill does not extend beyond end of this segment, because this segment is not full.
				}			
			}
		}

		// Only recompute if the buffers need redrawing, the current value changes more than 1% of the max or
		// the current value moves back.
		if (mBuffersNeedRedraw ||
			(target < mTargetValue) ||
			((target - mTargetValue) >= (mTargetMaxValue / 100))) {
			mTargetValue = target;
			mTargetHeight = Math.floor((mTargetValue * 1.0 / mTargetMaxValue) * mHeight);
		}
	}

	function onSettingsChanged() {
		mBuffersNeedRecreate = true;

		// #18 Only read separator width from layout if multi segment style is selected.
		if (GOAL_METER_STYLE[App.getApp().getProperty("GoalMeterStyle")] == :MULTI_SEGMENTS) {

			// Force recalculation of mSegments in setValues() if mSeparator is about to change.
			if (mSeparator != mLayoutSeparator) {
				mMaxValue = null;
			}

			mSeparator = mLayoutSeparator;
			
		} else {

			// Force recalculation of mSegments in setValues() if mSeparator is about to change.
			if (mSeparator != 0) {
				mMaxValue = null;
			}

			mSeparator = 0;
		}
	}

	// Different draw algorithms have been tried:
	// 1. Draw each segment as a circle, clipped to a rectangle of the desired height, direct to screen DC.
	//    Intuitive, but expensive.
	// 2. Buffered drawing: a buffer each for filled and unfilled segments (full height). Each buffer drawn as a single circle
	//    (only the part that overlaps the buffer DC is visible). Segments created by drawing horizontal lines of background
	//    colour. Screen DC is drawn from combination of two buffers, clipped to the desired fill height.
	// 3. Unbuffered drawing: no buffer, and no clip support. Want common drawBuffer() function, so draw each segment as
	//    rectangle, then draw circular background colour mask between both meters. This requires an extra drawable in the layout,
	//    expensive, so only use this strategy for unbuffered drawing. For buffered, the mask can be drawn into each buffer.
	function draw(dc) {
		if (GOAL_METER_STYLE[App.getApp().getProperty("GoalMeterStyle")] == :HIDDEN) {
			return;
		}

		var left;
		var top;

		if (mSide == :left) {
			left = 0;
		} else {
			left = dc.getWidth() - mWidth;
		}

		top = (dc.getHeight() - mHeight) / 2;

		var backgroundColour = App.getApp().getProperty("BackgroundColour");
		var meterBackgroundColour = App.getApp().getProperty("MeterBackgroundColour");
		var themeColour = App.getApp().getProperty("ThemeColour");
		
		if ((mBackgroundColour != backgroundColour) ||
			(mMeterBackgroundColour != meterBackgroundColour) ||
			(mThemeColour != themeColour)) {
			mBackgroundColour = backgroundColour;
			mMeterBackgroundColour = meterBackgroundColour;
			mThemeColour = themeColour;
			RefreshPalettes();
		}
		
		// #21 Force unbuffered drawing on fr735xt (CIQ 2.x) to reduce memory usage.
		// Now changed to use buffered drawing only on round watches.
		if ((Graphics has :BufferedBitmap) && (Graphics.Dc has :setClip) && (Sys.getDeviceSettings().screenShape == Sys.SCREEN_SHAPE_ROUND)) {
			drawBuffered(dc, left, top);
		} else {
			drawUnbuffered(dc, left, top);
		}
	}

	function RefreshPalettes() {
		mPaletteEmpty = null;
		mPalette1x = null;
		mPalette2x = null;
		mPaletteTarget = null;

		mPaletteEmpty =
			[
				mBackgroundColour,
				mMeterBackgroundColour
			];
		mPalette1x =
			[
				mBackgroundColour,
				Helpers.GetHeatMapColour(1, 10),
				Helpers.GetHeatMapColour(2, 10),
				Helpers.GetHeatMapColour(3, 10),
				Helpers.GetHeatMapColour(4, 10),
				Helpers.GetHeatMapColour(5, 10),
				Helpers.GetHeatMapColour(6, 10),
				Helpers.GetHeatMapColour(7, 10),
				Helpers.GetHeatMapColour(8, 10),
				Helpers.GetHeatMapColour(9, 10),
				Helpers.GetHeatMapColour(10, 10)
			];
		mPalette2x =
			[
				mBackgroundColour,
				Helpers.GetHeatMapColour(11, 10),
				Helpers.GetHeatMapColour(12, 10),
				Helpers.GetHeatMapColour(13, 10),
				Helpers.GetHeatMapColour(14, 10),
				Helpers.GetHeatMapColour(15, 10),
				Helpers.GetHeatMapColour(16, 10),
				Helpers.GetHeatMapColour(17, 10),
				Helpers.GetHeatMapColour(18, 10),
				Helpers.GetHeatMapColour(19, 10),
				Helpers.GetHeatMapColour(20, 10)
			];
		mPaletteTarget =
			[
				mBackgroundColour,
				mThemeColour
			];
	}

	// Redraw buffers if dirty, then draw from buffer to screen: from filled buffer up to fill height, then from empty buffer for
	// remaining height.
	(:buffered)
	function drawBuffered(dc, left, top) {
		var emptyBufferDc;
		var filledBuffer1xDc;
		var filledBuffer2xDc;
		var targetBufferDc;

		var clipBottom;
		var clipTop;
		var clipHeight;

		var halfScreenDcWidth = (dc.getWidth() / 2);
		var x;
		var radius;
		
		// Recreate buffers only if this is the very first draw(), or if optimised colour palette has changed.
		if (mBuffersNeedRecreate) {
			mEmptyBuffer = null;
			mFilledBuffer1x = null;
			mFilledBuffer2x = null;
			mTargetBuffer = null;

			mEmptyBuffer = createSegmentBuffer(mPaletteEmpty);
			mFilledBuffer1x = createSegmentBuffer(mPalette1x);
			mFilledBuffer2x = createSegmentBuffer(mPalette2x);
			mTargetBuffer = createSegmentBuffer(mPaletteTarget);

			mBuffersNeedRecreate = false;
			mBuffersNeedRedraw = true; // Ensure newly-created buffers are drawn next.
		}

		// Redraw buffers only if maximum value changes.
		if (mBuffersNeedRedraw) {

			// Clear both buffers with background colour.	
			emptyBufferDc = mEmptyBuffer.getDc();
			emptyBufferDc.setColor(Graphics.COLOR_TRANSPARENT, mBackgroundColour);
			emptyBufferDc.clear();

			filledBuffer1xDc = mFilledBuffer1x.getDc();			
			filledBuffer1xDc.setColor(Graphics.COLOR_TRANSPARENT, mBackgroundColour);
			filledBuffer1xDc.clear();

			filledBuffer2xDc = mFilledBuffer2x.getDc();			
			filledBuffer2xDc.setColor(Graphics.COLOR_TRANSPARENT, mBackgroundColour);
			filledBuffer2xDc.clear();

			targetBufferDc = mTargetBuffer.getDc();			
			targetBufferDc.setColor(Graphics.COLOR_TRANSPARENT, mBackgroundColour);
			targetBufferDc.clear();

			// Draw full fill height for each buffer.
			drawSegments(emptyBufferDc, 0, 0, mEmptyBuffer.getPalette(), mSegments, 0, mHeight);
			drawSegments(filledBuffer1xDc, 0, 0, mFilledBuffer1x.getPalette(), mSegments, 0, mHeight);
			drawSegments(filledBuffer2xDc, 0, 0, mFilledBuffer2x.getPalette(), mSegments, 0, mHeight);
			drawSegments(targetBufferDc, 0, 0, mTargetBuffer.getPalette(), getSegments(1), 0, mHeight);

			// For arc meters, draw circular mask for each buffer.
			if (mShape == :arc) {

				if (mSide == :left) {
					x = halfScreenDcWidth; // Beyond right edge of bufferDc.
				} else {
					x = mWidth - halfScreenDcWidth - 1; // Beyond left edge of bufferDc.
				}
				radius = halfScreenDcWidth - mStroke;

				emptyBufferDc.setColor(mBackgroundColour, Graphics.COLOR_TRANSPARENT);
				emptyBufferDc.fillCircle(x, (mHeight / 2), radius);

				filledBuffer1xDc.setColor(mBackgroundColour, Graphics.COLOR_TRANSPARENT);
				filledBuffer1xDc.fillCircle(x, (mHeight / 2), radius);

				filledBuffer2xDc.setColor(mBackgroundColour, Graphics.COLOR_TRANSPARENT);
				filledBuffer2xDc.fillCircle(x, (mHeight / 2), radius);

				targetBufferDc.setColor(mBackgroundColour, Graphics.COLOR_TRANSPARENT);
				targetBufferDc.fillCircle(x, (mHeight / 2), radius - mStroke / 2 );
			}

			mBuffersNeedRedraw = false;
		}

		var bufferBottom = null;
		var bufferTop = null;
		
		if (mFillType == :FILL_1x) {
			bufferBottom = mFilledBuffer1x;
			bufferTop = mEmptyBuffer;
		} else if (mFillType == :FILL_2x) {
			bufferBottom = mFilledBuffer2x;
			bufferTop = mFilledBuffer1x;
		} 

		// Draw bottom segments.		
		clipBottom = dc.getHeight() - top;
		clipTop = clipBottom - mFillHeight;
		clipHeight = clipBottom - clipTop;
		if (clipHeight > 0) {
			dc.setClip(left, clipTop, mWidth, clipHeight);
			dc.drawBitmap(left, top, bufferBottom);
		}

		// Draw top segments.
		clipBottom = clipTop;
		clipTop = top;
		clipHeight = clipBottom - clipTop;
		if (clipHeight > 0) {
			dc.setClip(left, clipTop, mWidth, clipHeight);
			dc.drawBitmap(left, top, bufferTop);
		}
		
		clipHeight = 3;
		
		if (mMeterBackgroundColour == mBackgroundColour) {
			// Draw target gauge (0).
			clipBottom = dc.getHeight() - top;
			clipTop = clipBottom - clipHeight;
			dc.setClip(left, clipTop, mWidth, clipHeight);
			dc.drawBitmap(left, top, mTargetBuffer);
	
			// Draw target gauge (max).
			clipTop = top;
			clipBottom = top + clipHeight;
			dc.setClip(left, clipTop, mWidth, clipHeight);
			dc.drawBitmap(left, top, mTargetBuffer);
		}

		// Draw target gauge.
		clipBottom = dc.getHeight() - top - mTargetHeight;
		clipTop = clipBottom - clipHeight;
		if (clipTop < top) {
			clipBottom += (top - clipTop); 
			clipTop = top;
		}
		dc.setClip(left, clipTop, mWidth, clipHeight);
		dc.drawBitmap(left, top, mTargetBuffer);

		dc.clearClip();
	}

	// Use restricted palette, to conserve memory (four buffers per watchface).
	(:buffered)
	function createSegmentBuffer(fillColours) {
		return new Graphics.BufferedBitmap({
			:width => mWidth,
			:height => mHeight,
			:palette => fillColours
		});
	}

	function drawUnbuffered(dc, left, top) {
		var paletteBottom = null;
		var paletteTop = null;

		if (mFillType == :FILL_1x) {
			paletteBottom = mPallete1x;
			paletteTop = mPalleteEmpty;
		} else if (mFillType == :FILL_2x) {
			paletteBottom = mPallete2x;
			paletteTop = mPallete1x;
		} 
	
		// Bottom segments.
		drawSegments(dc, left, top, paletteBottom, mSegments, 0, mFillHeight);

		// Top segments.
		drawSegments(dc, left, top, paletteTop, mSegments, mFillHeight, mHeight);
	}

	// dc can be screen or buffer DC, depending on drawing mode.
	// x and y are co-ordinates of top-left corner of meter.
	// start/endFillHeight are pixel fill heights including separators, starting from zero at bottom.
	function drawSegments(dc, x, y, fillColours, segments, startFillHeight, endFillHeight) {
		var segmentStart = 0;
		var segmentEnd;

		var fillStart;
		var fillEnd;
		var fillHeight;

		y += mHeight; // Start from bottom.

		// Draw rectangles, separator-width apart vertically, starting from bottom.
		var iFillColour = fillColours.size() - segments.size();
		for (var i = 0; i < segments.size(); ++i, ++iFillColour) {
			if (iFillColour < 1) {
				iFillColour = 1;
			} else if (iFillColour >= fillColours.size()) {
				iFillColour = fillColours.size() - 1;
			}

			dc.setColor(fillColours[iFillColour], Graphics.COLOR_TRANSPARENT /* Graphics.COLOR_RED */);
		
			segmentEnd = segmentStart + segments[i];

			// Full segment is filled.
			if ((segmentStart >= startFillHeight) && (segmentEnd <= endFillHeight)) {
				fillStart = segmentStart;
				fillEnd = segmentEnd;

			// Bottom of this segment is filled.
			} else if (segmentStart >= startFillHeight) {
				fillStart = segmentStart;
				fillEnd = endFillHeight;

			// Top of this segment is filled.
			} else if (segmentEnd <= endFillHeight) {
				fillStart = startFillHeight;
				fillEnd = segmentEnd;
			
			// Segment is not filled.
			} else {
				fillStart = 0;
				fillEnd = 0;
			}

			//Sys.println("segment     : " + segmentStart + "-->" + segmentEnd);
			//Sys.println("segment fill: " + fillStart + "-->" + fillEnd);

			fillHeight = fillEnd - fillStart;
			if (fillHeight) {
				//Sys.println("draw segment: " + x + ", " + (y - fillStart - fillHeight) + ", " + mWidth + ", " + fillHeight);
				dc.fillRectangle(x, y - fillStart - fillHeight, mWidth, fillHeight);
			}

			segmentStart = segmentEnd + mSeparator;
		}
	}

	// Return array of segment heights.
	// Last segment may be partial segment; if so, ensure its height is at least 1 pixel.
	// Segment heights rounded to nearest pixel, so neighbouring whole segments may differ in height by a pixel.
	function getSegments(numSegments) {
		var segmentScale = (mMaxValue * 1.0) / numSegments; // Value each whole segment represents.
		var numSeparators = numSegments - 1;
		var totalSegmentHeight = mHeight - (numSeparators * mSeparator); // Subtract total separator height from full height.		
		var segmentHeight = totalSegmentHeight * 1.0 / numSegments; // Force floating-point division.
		//Sys.println("segmentHeight " + segmentHeight);

		var segments = new [numSegments];
		var start, end, height;

		for (var i = 0; i < segments.size(); ++i) {
			start = Math.round(i * segmentHeight);
			end = Math.round((i + 1) * segmentHeight);

			// Last segment is partial.
			if (end > totalSegmentHeight) {
				end = totalSegmentHeight;
			}

			height = end - start;

			segments[i] = height;
			//Sys.println("segment " + i + " height " + height);
		}

		return segments;
	}
}