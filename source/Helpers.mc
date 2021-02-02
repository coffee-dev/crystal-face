using Toybox.Graphics;
using Toybox.Lang;
using Toybox.Math;

class Helpers {
	static function GetHeatMapColour(level, levelMax) {
		var red = 0;
		var green = 0;
		var blue = 0;
		
		if (level <= levelMax) {
			var levelScale = (level * 1.0) / levelMax;
			var colourScaleRange = (0xFF - 0xAA) + 0xFF + 0xFF;
			var colourDelta = Math.ceil(levelScale * colourScaleRange).toNumber();

			red = 0xAA;
			green = 0x00;
			blue = 0x00;
			
			if ((red + colourDelta) > 0xFF) {
				colourDelta -= (0xFF - red);
				red = 0xFF;
				
				if ((green + colourDelta) > 0xFF) {
					colourDelta -= (0xFF - green);
					green = 0xFF;
					red -= colourDelta;
					if (red < 0) {
						red = 0;
					}
				}
				else {
					green += colourDelta;
				}
			}
			else {
				red += colourDelta;
			}
		}
		else if (level <= (2 * levelMax)) {
			var levelScale = ((level - levelMax) * 1.0) / levelMax;
			var colourScaleRange = 0xFF;
			var colourDelta = Math.ceil(levelScale * colourScaleRange).toNumber();

			red = 0x00;
			green = 0xFF;
			blue = 0xFF;
			
			if (colourDelta <= green) {
				green -= colourDelta;
			}
			else {
				green = 0x00;
			}
		}
		else if (level <= (3 * levelMax)) {
			var levelScale = ((level - 2 * levelMax) * 1.0) / levelMax;
			var colourScaleRange = 0xFF - 0x55;
			var colourDelta = Math.ceil(levelScale * colourScaleRange).toNumber();

			red = 0xFF;
			green = 0x00;
			blue = 0xFF;
			
			if (colourDelta <= red) {
				red -= colourDelta;
			}
			else {
				red = 0x55;
			}
		}
		else {
			red = 0xAA;
			green = 0x00;
			blue = 0xFF;
		}
		
		return (red << 16) + (green << 8) + blue; 
	}
}
