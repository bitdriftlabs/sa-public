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
  activeColor = '#111827',
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
              : {backgroundColor: 'rgba(17,24,39,0.12)'},
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
