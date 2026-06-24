import React from 'react';
import {View, StyleSheet} from 'react-native';

type StepIndicatorProps = {
  currentStep: number;
  totalSteps?: number;
  activeColor?: string;
};

export const StepIndicator: React.FC<StepIndicatorProps> = ({
  currentStep,
  totalSteps = 7,
  activeColor = '#FFFFFF',
}) => {
  return (
    <View style={styles.container}>
      {Array.from({length: totalSteps}, (_, index) => (
        <View
          key={index}
          style={[
            styles.dot,
            index < currentStep
              ? {backgroundColor: activeColor}
              : {backgroundColor: 'rgba(255,255,255,0.26)'},
          ]}
        />
      ))}
    </View>
  );
};

const styles = StyleSheet.create({
  container: {
    flexDirection: 'row',
    justifyContent: 'center',
    alignItems: 'center',
    gap: 7,
  },
  dot: {
    width: 10,
    height: 10,
    borderRadius: 5,
  },
});
