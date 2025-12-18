import * as React from "react";
import { View, StyleSheet } from "react-native";
import Svg, { Circle, Rect, Path } from "react-native-svg";

export function CartSVGThing() {
  return (
    <View style={styles.svgContainer}>
      <Svg height="100" width="100" viewBox="0 0 100 100">
        <Circle
          cx="50"
          cy="50"
          r="40"
          stroke="purple"
          strokeWidth="2"
          fill="yellow"
        />
        <Rect
          x="20"
          y="20"
          width="60"
          height="60"
          fill="rgba(0,0,255,0.3)"
        />
        <Path
          d="M 20 50 Q 50 20, 80 50"
          stroke="red"
          strokeWidth="2"
          fill="none"
        />
      </Svg>
    </View>
  );
}

const styles = StyleSheet.create({
  svgContainer: {
    alignItems: "center",
    justifyContent: "center",
    padding: 20,
    backgroundColor: "#f0f0f0",
  },
});

